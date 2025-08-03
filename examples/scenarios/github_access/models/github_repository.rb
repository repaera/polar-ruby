# frozen_string_literal: true

class GithubRepository < ApplicationRecord
  has_many :repository_accesses, dependent: :destroy
  has_many :users_with_access, through: :repository_accesses, source: :user
  has_many :package_repositories, dependent: :destroy
  has_many :repository_packages, through: :package_repositories

  validates :name, presence: true
  validates :full_name, presence: true, uniqueness: true
  validates :owner, presence: true
  validates :github_id, presence: true, uniqueness: true

  enum access_type: {
    individual: 'individual',
    package: 'package', 
    organization: 'organization'
  }

  enum category: {
    library: 'library',
    framework: 'framework',
    template: 'template',
    course: 'course',
    tool: 'tool',
    documentation: 'documentation'
  }

  scope :active, -> { where(active: true) }
  scope :featured, -> { where(featured: true) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :with_access_for_user, ->(user) {
    joins(:repository_accesses)
      .where(repository_accesses: { 
        user: user, 
        status: 'active',
        expires_at: [nil, Time.current..] 
      })
  }

  before_validation :set_full_name, if: -> { name.present? && owner.present? }
  after_create :sync_from_github
  after_update :update_github_repository, if: :saved_change_to_description?

  def self.import_from_github(full_name, github_client)
    repo_data = github_client.repository(full_name)
    
    create_or_update_from_github_data(repo_data)
  end

  def self.create_or_update_from_github_data(repo_data)
    repository = find_or_initialize_by(github_id: repo_data[:id].to_s)
    
    repository.assign_attributes(
      name: repo_data[:name],
      full_name: repo_data[:full_name],
      owner: repo_data[:owner][:login],
      description: repo_data[:description],
      clone_url: repo_data[:clone_url],
      ssh_url: repo_data[:ssh_url],
      html_url: repo_data[:html_url],
      private: repo_data[:private],
      default_branch: repo_data[:default_branch],
      language: repo_data[:language],
      size_kb: repo_data[:size],
      stargazers_count: repo_data[:stargazers_count],
      forks_count: repo_data[:forks_count],
      last_pushed_at: repo_data[:pushed_at] ? Time.parse(repo_data[:pushed_at]) : nil
    )
    
    repository.save!
    repository
  end

  def grant_access_to_user(user, **options)
    return false unless user.github_connected?
    
    access_level = options[:access_level] || 'read'
    expires_at = options[:expires_at]
    purchase_reference = options[:purchase_reference]
    polar_order_id = options[:polar_order_id]
    access_source = options[:access_source] || 'purchase'
    
    # Check if user already has access
    existing_access = repository_accesses.find_by(user: user)
    
    if existing_access
      existing_access.update!(
        access_level: access_level,
        expires_at: expires_at,
        purchase_reference: purchase_reference,
        polar_order_id: polar_order_id,
        access_source: access_source,
        status: 'pending',
        granted_at: Time.current
      )
    else
      existing_access = repository_accesses.create!(
        user: user,
        access_level: access_level,
        expires_at: expires_at,
        purchase_reference: purchase_reference,
        polar_order_id: polar_order_id,
        access_source: access_source,
        status: 'pending',
        granted_at: Time.current
      )
    end
    
    # Send GitHub invitation
    GitHubInvitationJob.perform_later(existing_access.id)
    
    existing_access
  end

  def revoke_access_for_user(user, reason: nil)
    access = repository_accesses.find_by(user: user)
    return false unless access
    
    access.update!(
      status: 'revoked',
      revoked_at: Time.current,
      revoked_reason: reason
    )
    
    # Remove from GitHub repository
    GitHubRevocationJob.perform_later(access.id)
    
    true
  end

  def user_has_active_access?(user)
    repository_accesses.active
                      .where(user: user)
                      .where('expires_at IS NULL OR expires_at > ?', Time.current)
                      .exists?
  end

  def active_users_count
    repository_accesses.active
                      .where('expires_at IS NULL OR expires_at > ?', Time.current)
                      .count
  end

  def total_revenue
    # Calculate revenue from individual purchases and package purchases
    individual_revenue = repository_accesses.where.not(polar_order_id: nil)
                                           .joins("LEFT JOIN orders ON orders.polar_order_id = repository_accesses.polar_order_id")
                                           .sum("COALESCE(orders.amount, #{price || 0})")
    
    package_revenue = repository_packages.sum do |package|
      package.repository_accesses_count * package.price
    end
    
    individual_revenue + package_revenue
  end

  def sync_from_github!
    return false unless github_client_available?
    
    begin
      repo_data = github_client.repository(full_name)
      self.class.create_or_update_from_github_data(repo_data)
      true
    rescue => e
      Rails.logger.error "Failed to sync repository #{full_name}: #{e.message}"
      false
    end
  end

  def formatted_price
    return 'Free' if price.nil? || price.zero?
    "$#{price.to_f}"
  end

  def readme_url
    "#{html_url}/blob/#{default_branch}/README.md"
  end

  def documentation_url
    metadata['documentation_url'] || "#{html_url}/wiki"
  end

  def demo_url
    metadata['demo_url']
  end

  def license_url
    "#{html_url}/blob/#{default_branch}/LICENSE"
  end

  def can_grant_access?
    active? && !access_expired? && !at_user_limit?
  end

  def access_expired?
    access_expires_at && access_expires_at <= Time.current
  end

  def at_user_limit?
    max_users && active_users_count >= max_users
  end

  def access_instructions_formatted
    return access_instructions if access_instructions.present?
    
    default_instructions
  end

  def repository_stats
    {
      total_users: repository_accesses.count,
      active_users: active_users_count,
      pending_invitations: repository_accesses.where(status: 'pending').count,
      expired_accesses: repository_accesses.where('expires_at < ?', Time.current).count,
      total_revenue: total_revenue,
      average_revenue_per_user: active_users_count > 0 ? total_revenue / active_users_count : 0
    }
  end

  def similar_repositories(limit = 5)
    self.class.active
        .where(category: category)
        .where.not(id: id)
        .limit(limit)
  end

  private

  def set_full_name
    self.full_name = "#{owner}/#{name}"
  end

  def sync_from_github
    SyncRepositoryJob.perform_later(id) if github_id.present?
  end

  def update_github_repository
    UpdateGitHubRepositoryJob.perform_later(id)
  end

  def github_client_available?
    # Check if we have a system GitHub token or user token available
    ENV['GITHUB_ACCESS_TOKEN'].present? || 
    User.with_github_access.where(admin: true).exists?
  end

  def github_client
    @github_client ||= if ENV['GITHUB_ACCESS_TOKEN'].present?
                        GitHubApiClient.new(ENV['GITHUB_ACCESS_TOKEN'])
                      else
                        admin_user = User.with_github_access.where(admin: true).first
                        admin_user&.github_client
                      end
  end

  def default_instructions
    case category
    when 'library'
      "1. Clone the repository\n2. Install dependencies\n3. Import the library in your project"
    when 'framework'
      "1. Clone the repository\n2. Follow the setup guide in README.md\n3. Run the development server"
    when 'template'
      "1. Use this template to create a new repository\n2. Customize for your needs\n3. Deploy following the included guide"
    when 'course'
      "1. Clone the repository\n2. Follow lessons in order\n3. Complete exercises in each chapter"
    else
      "1. Clone the repository\n2. Follow the README.md instructions\n3. Refer to documentation for usage"
    end
  end
end