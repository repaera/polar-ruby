# frozen_string_literal: true

class GitHubAccessWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # Polar webhooks for repository access purchases
  def polar_webhook
    payload = request.body.read
    signature = request.headers['Polar-Signature']
    
    unless verify_polar_signature(payload, signature)
      head :unauthorized
      return
    end
    
    event = JSON.parse(payload)
    
    case event['type']
    when 'order.completed'
      handle_repository_purchase(event['data'])
    when 'subscription.created'
      handle_subscription_access(event['data'])
    when 'subscription.cancelled'
      handle_subscription_cancelled(event['data'])
    when 'refund.created'
      handle_access_refund(event['data'])
    else
      Rails.logger.info "Unhandled repository webhook event: #{event['type']}"
    end
    
    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error "Invalid JSON in repository webhook: #{e.message}"
    head :bad_request
  rescue => e
    Rails.logger.error "Repository webhook processing error: #{e.message}"
    head :internal_server_error
  end

  # GitHub webhooks for repository events
  def github_webhook
    payload = request.body.read
    signature = request.headers['X-Hub-Signature-256']
    
    unless verify_github_signature(payload, signature)
      head :unauthorized
      return
    end
    
    event = JSON.parse(payload)
    event_type = request.headers['X-GitHub-Event']
    
    case event_type
    when 'member'
      handle_member_event(event)
    when 'membership'
      handle_membership_event(event)
    when 'repository'
      handle_repository_event(event)
    when 'push'
      handle_repository_activity(event)
    when 'release'
      handle_release_event(event)
    else
      Rails.logger.info "Unhandled GitHub webhook event: #{event_type}"
    end
    
    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error "Invalid JSON in GitHub webhook: #{e.message}"
    head :bad_request
  rescue => e
    Rails.logger.error "GitHub webhook processing error: #{e.message}"
    head :internal_server_error
  end

  private

  # Polar webhook handlers
  def handle_repository_purchase(order_data)
    user = find_user_by_customer_id(order_data['customer_id'])
    return unless user

    Rails.logger.info "Processing repository purchase for user #{user.id}"
    
    package_id = order_data['metadata']&.dig('package_id')
    repository_id = order_data['metadata']&.dig('repository_id')
    
    if package_id
      handle_package_purchase(user, package_id, order_data)
    elsif repository_id
      handle_individual_repository_purchase(user, repository_id, order_data)
    else
      Rails.logger.warn "No package_id or repository_id in order metadata: #{order_data['id']}"
    end
  end

  def handle_package_purchase(user, package_id, order_data)
    package = RepositoryPackage.find_by(id: package_id)
    return unless package

    Rails.logger.info "Granting package access: #{package.name} to user #{user.id}"
    
    User.transaction do
      # Grant access to all repositories in the package
      access_results = []
      
      package.github_repositories.each do |repository|
        access = repository.grant_access_to_user(
          user,
          access_level: 'read',
          expires_at: calculate_access_expiry(package, order_data),
          purchase_reference: "package_#{package.id}",
          polar_order_id: order_data['id'],
          access_source: 'package_purchase'
        )
        
        access_results << access if access
      end
      
      # Send purchase confirmation email
      RepositoryMailer.package_purchased(user, package, access_results).deliver_later
      
      # Track purchase event
      track_repository_event(user, 'package_purchased', {
        package_id: package_id,
        package_name: package.name,
        repository_count: package.github_repositories.count,
        order_id: order_data['id'],
        amount: order_data['amount'] / 100.0
      })
    end
  end

  def handle_individual_repository_purchase(user, repository_id, order_data)
    repository = GithubRepository.find_by(id: repository_id)
    return unless repository

    Rails.logger.info "Granting individual repository access: #{repository.name} to user #{user.id}"
    
    access = repository.grant_access_to_user(
      user,
      access_level: 'read',
      expires_at: calculate_individual_access_expiry(repository, order_data),
      purchase_reference: "repository_#{repository.id}",
      polar_order_id: order_data['id'],
      access_source: 'individual_purchase'
    )
    
    if access
      # Send purchase confirmation email
      RepositoryMailer.repository_purchased(user, repository, access).deliver_later
      
      track_repository_event(user, 'repository_purchased', {
        repository_id: repository_id,
        repository_name: repository.name,
        order_id: order_data['id'],
        amount: order_data['amount'] / 100.0
      })
    end
  end

  def handle_subscription_access(subscription_data)
    user = find_user_by_customer_id(subscription_data['customer_id'])
    return unless user

    # Determine which repositories this subscription grants access to
    product_id = subscription_data['product_id']
    repositories = find_repositories_for_product(product_id)
    
    repositories.each do |repository|
      access = repository.grant_access_to_user(
        user,
        access_level: 'read',
        expires_at: parse_timestamp(subscription_data['current_period_end']),
        purchase_reference: "subscription_#{subscription_data['id']}",
        polar_order_id: subscription_data['id'],
        access_source: 'subscription'
      )
    end
    
    if repositories.any?
      RepositoryMailer.subscription_access_granted(user, repositories, subscription_data).deliver_later
    end
  end

  def handle_subscription_cancelled(subscription_data)
    # Find and revoke access for subscription-based repositories
    accesses = RepositoryAccess.where(
      purchase_reference: "subscription_#{subscription_data['id']}"
    ).includes(:user, :github_repository)
    
    accesses.each do |access|
      access.github_repository.revoke_access_for_user(
        access.user,
        reason: 'Subscription cancelled'
      )
    end
  end

  def handle_access_refund(refund_data)
    # Find original purchase and revoke access
    polar_order_id = refund_data['order_id']
    accesses = RepositoryAccess.where(polar_order_id: polar_order_id)
                              .includes(:user, :github_repository)
    
    accesses.each do |access|
      access.github_repository.revoke_access_for_user(
        access.user,
        reason: 'Purchase refunded'
      )
      
      # Send refund notification
      RepositoryMailer.access_refunded(access.user, access.github_repository).deliver_later
    end
  end

  # GitHub webhook handlers
  def handle_member_event(event)
    action = event['action']
    member = event['member']
    repository = event['repository']
    
    case action
    when 'added'
      handle_member_added(member, repository)
    when 'removed'
      handle_member_removed(member, repository)
    end
  end

  def handle_member_added(member, repository_data)
    # Update repository access status when user accepts invitation
    github_username = member['login']
    user = User.find_by(github_username: github_username)
    return unless user
    
    github_repo = GithubRepository.find_by(github_id: repository_data['id'].to_s)
    return unless github_repo
    
    access = user.repository_access_for(github_repo)
    if access && access.status == 'invited'
      access.update!(
        status: 'active',
        invitation_accepted_at: Time.current,
        last_accessed_at: Time.current
      )
      
      # Send access confirmation email
      RepositoryMailer.access_activated(user, github_repo, access).deliver_later
      
      track_repository_event(user, 'repository_access_activated', {
        repository_id: github_repo.id,
        repository_name: github_repo.name
      })
    end
  end

  def handle_member_removed(member, repository_data)
    # Track when user is removed from repository
    github_username = member['login']
    user = User.find_by(github_username: github_username)
    return unless user
    
    github_repo = GithubRepository.find_by(github_id: repository_data['id'].to_s)
    return unless github_repo
    
    access = user.repository_access_for(github_repo)
    if access && access.status == 'active'
      access.update!(
        status: 'revoked',
        revoked_at: Time.current,
        revoked_reason: 'Removed from GitHub repository'
      )
      
      track_repository_event(user, 'repository_access_revoked', {
        repository_id: github_repo.id,
        repository_name: github_repo.name,
        reason: 'github_removal'
      })
    end
  end

  def handle_membership_event(event)
    # Handle organization membership changes
    action = event['action']
    member = event['member']
    organization = event['organization']
    
    # Track organization membership for enterprise customers
    track_organization_event(member['login'], action, organization['login'])
  end

  def handle_repository_event(event)
    # Handle repository updates, creation, deletion
    action = event['action']
    repository = event['repository']
    
    case action
    when 'created'
      sync_new_repository(repository)
    when 'deleted'
      handle_repository_deletion(repository)
    when 'privatized'
      handle_repository_privatized(repository)
    when 'publicized'
      handle_repository_publicized(repository)
    end
  end

  def handle_repository_activity(event)
    # Track repository usage (pushes, commits)
    repository = event['repository']
    pusher = event['pusher']
    
    github_repo = GithubRepository.find_by(github_id: repository['id'].to_s)
    return unless github_repo
    
    user = User.find_by(github_username: pusher['name'])
    if user
      access = user.repository_access_for(github_repo)
      if access
        access.increment!(:access_count)
        access.touch(:last_accessed_at)
      end
    end
  end

  def handle_release_event(event)
    # Notify users of new releases in repositories they have access to
    action = event['action']
    release = event['release']
    repository = event['repository']
    
    if action == 'published'
      notify_users_of_release(repository, release)
    end
  end

  # Helper methods
  def find_user_by_customer_id(customer_id)
    User.find_by(polar_customer_id: customer_id)
  end

  def find_repositories_for_product(product_id)
    # Map product IDs to repositories/packages
    package = RepositoryPackage.find_by(polar_product_id: product_id)
    if package
      package.github_repositories
    else
      repository = GithubRepository.find_by(polar_product_id: product_id)
      repository ? [repository] : []
    end
  end

  def calculate_access_expiry(package, order_data)
    case package.access_duration
    when 'permanent'
      nil
    when '1_year'
      1.year.from_now
    when 'custom'
      # Parse from package metadata or order data
      parse_timestamp(order_data['metadata']&.dig('expires_at'))
    else
      nil
    end
  end

  def calculate_individual_access_expiry(repository, order_data)
    # Individual repositories typically grant permanent access
    repository.access_expires_at
  end

  def parse_timestamp(timestamp)
    return nil unless timestamp
    Time.parse(timestamp)
  rescue ArgumentError
    nil
  end

  def sync_new_repository(repository_data)
    # Automatically sync new repositories if they belong to tracked organizations
    GithubRepository.create_or_update_from_github_data(repository_data)
  end

  def handle_repository_deletion(repository_data)
    github_repo = GithubRepository.find_by(github_id: repository_data['id'].to_s)
    if github_repo
      # Revoke all access and mark repository as inactive
      github_repo.repository_accesses.update_all(
        status: 'revoked',
        revoked_at: Time.current,
        revoked_reason: 'Repository deleted'
      )
      
      github_repo.update!(active: false)
    end
  end

  def handle_repository_privatized(repository_data)
    github_repo = GithubRepository.find_by(github_id: repository_data['id'].to_s)
    github_repo&.update!(private: true)
  end

  def handle_repository_publicized(repository_data)
    github_repo = GithubRepository.find_by(github_id: repository_data['id'].to_s)
    if github_repo
      github_repo.update!(private: false)
      
      # Optionally revoke paid access since repo is now public
      if github_repo.price&.positive?
        notify_public_repository_change(github_repo)
      end
    end
  end

  def notify_users_of_release(repository_data, release_data)
    github_repo = GithubRepository.find_by(github_id: repository_data['id'].to_s)
    return unless github_repo
    
    # Notify users who have access to this repository
    users_with_access = github_repo.users_with_access.distinct
    
    users_with_access.each do |user|
      RepositoryMailer.new_release_available(user, github_repo, release_data).deliver_later
    end
  end

  def notify_public_repository_change(github_repo)
    # Notify paying users that repository is now public
    github_repo.users_with_access.each do |user|
      RepositoryMailer.repository_now_public(user, github_repo).deliver_later
    end
  end

  def track_repository_event(user, event_type, properties = {})
    Analytics.track(
      user_id: user.id,
      event: event_type,
      properties: properties.merge({
        timestamp: Time.current,
        github_username: user.github_username
      })
    )
  rescue => e
    Rails.logger.error "Failed to track repository event: #{e.message}"
  end

  def track_organization_event(github_username, action, organization)
    user = User.find_by(github_username: github_username)
    return unless user
    
    track_repository_event(user, 'organization_membership_changed', {
      action: action,
      organization: organization
    })
  end

  def verify_polar_signature(payload, signature)
    # Implement Polar signature verification
    true
  end

  def verify_github_signature(payload, signature)
    # Implement GitHub signature verification
    return true unless ENV['GITHUB_WEBHOOK_SECRET']
    
    expected_signature = 'sha256=' + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('sha256'),
      ENV['GITHUB_WEBHOOK_SECRET'],
      payload
    )
    
    Rack::Utils.secure_compare(signature, expected_signature)
  end
end