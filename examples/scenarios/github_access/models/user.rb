# frozen_string_literal: true

class User < ApplicationRecord
  has_many :repository_accesses, dependent: :destroy
  has_many :accessible_repositories, through: :repository_accesses, source: :github_repository
  
  encrypts :github_access_token

  validates :github_username, uniqueness: true, allow_nil: true
  validates :github_user_id, uniqueness: true, allow_nil: true

  scope :with_github_access, -> { where.not(github_access_token: nil) }
  scope :github_connected, -> { where.not(github_connected_at: nil) }

  def github_connected?
    github_access_token.present? && github_connected_at.present?
  end

  def github_profile_complete?
    github_connected? && github_username.present? && github_user_id.present?
  end

  def connect_github!(oauth_data)
    update!(
      github_username: oauth_data[:username],
      github_user_id: oauth_data[:user_id].to_s,
      github_access_token: oauth_data[:access_token],
      github_email: oauth_data[:email],
      github_name: oauth_data[:name],
      github_avatar_url: oauth_data[:avatar_url],
      github_profile_url: oauth_data[:profile_url],
      github_connected_at: Time.current,
      github_permissions: oauth_data[:permissions] || {}
    )
  end

  def disconnect_github!
    # Revoke all repository access first
    repository_accesses.active.find_each do |access|
      GitHubAccessManager.new(self).revoke_repository_access(
        access.github_repository,
        reason: 'GitHub account disconnected'
      )
    end
    
    update!(
      github_username: nil,
      github_user_id: nil,
      github_access_token: nil,
      github_email: nil,
      github_name: nil,
      github_avatar_url: nil,
      github_profile_url: nil,
      github_connected_at: nil,
      github_permissions: {}
    )
  end

  def has_repository_access?(repository)
    repository_accesses.active
                      .where(github_repository: repository)
                      .where('expires_at IS NULL OR expires_at > ?', Time.current)
                      .exists?
  end

  def repository_access_for(repository)
    repository_accesses.where(github_repository: repository).first
  end

  def active_repository_accesses
    repository_accesses.active.includes(:github_repository)
  end

  def expired_repository_accesses
    repository_accesses.where('expires_at < ?', Time.current)
  end

  def pending_invitations
    repository_accesses.where(status: 'pending').includes(:github_repository)
  end

  def grant_repository_access!(repository, **options)
    GitHubAccessManager.new(self).grant_repository_access(repository, **options)
  end

  def revoke_repository_access!(repository, reason: nil)
    GitHubAccessManager.new(self).revoke_repository_access(repository, reason: reason)
  end

  def purchase_repository_package(package_id)
    package = RepositoryPackage.find(package_id)
    
    begin
      checkout = create_repository_checkout(package)
      checkout['url']
    rescue => e
      Rails.logger.error "Repository package purchase failed: #{e.message}"
      nil
    end
  end

  def github_client
    @github_client ||= GitHubApiClient.new(github_access_token) if github_access_token
  end

  def sync_github_profile!
    return false unless github_connected?
    
    begin
      profile_data = github_client.user_profile
      
      update!(
        github_name: profile_data[:name],
        github_avatar_url: profile_data[:avatar_url],
        github_profile_url: profile_data[:html_url],
        github_email: profile_data[:email] || github_email
      )
      
      true
    rescue => e
      Rails.logger.error "Failed to sync GitHub profile for user #{id}: #{e.message}"
      false
    end
  end

  def repository_usage_stats
    {
      total_repositories: accessible_repositories.count,
      active_accesses: repository_accesses.active.count,
      expired_accesses: expired_repository_accesses.count,
      pending_invitations: pending_invitations.count,
      last_accessed: repository_accesses.maximum(:last_accessed_at),
      total_access_count: repository_accesses.sum(:access_count)
    }
  end

  def can_access_repository?(repository_id)
    return false unless github_connected?
    
    repository = GithubRepository.find(repository_id)
    has_repository_access?(repository)
  end

  def repository_access_expires_soon?(days_ahead = 7)
    repository_accesses.active
                      .where(expires_at: Time.current..days_ahead.days.from_now)
                      .exists?
  end

  def repositories_by_category
    accessible_repositories.joins(:repository_accesses)
                          .where(repository_accesses: { user: self, status: 'active' })
                          .group_by(&:category)
  end

  private

  def create_repository_checkout(package)
    Polar.client.checkouts.create({
      product_id: package.polar_product_id,
      customer: {
        email: email,
        external_id: id.to_s
      },
      success_url: Rails.application.routes.url_helpers.repositories_success_url(host: Rails.application.config.app_host),
      cancel_url: Rails.application.routes.url_helpers.repositories_url(host: Rails.application.config.app_host),
      metadata: {
        user_id: id,
        package_id: package.id,
        github_username: github_username
      }
    })
  end
end