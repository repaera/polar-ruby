# frozen_string_literal: true

class GitHubAccessManager
  include ActiveModel::Model
  
  attr_accessor :user
  
  def initialize(user)
    @user = user
  end

  def grant_repository_access(repository, **options)
    return failure("User must connect GitHub account first") unless user.github_connected?
    return failure("Repository access not available") unless repository.can_grant_access?
    
    begin
      User.transaction do
        # Create or update access record
        access = create_or_update_access_record(repository, options)
        
        # Send GitHub invitation
        send_github_invitation(access)
        
        # Track the grant event
        track_access_event('access_granted', repository, access)
        
        success("Access granted successfully", access: access)
      end
    rescue => e
      Rails.logger.error "Failed to grant repository access: #{e.message}"
      failure("Failed to grant access: #{e.message}")
    end
  end

  def revoke_repository_access(repository, reason: nil)
    access = user.repository_access_for(repository)
    return failure("No access found for this repository") unless access
    
    begin
      User.transaction do
        # Update access record
        access.update!(
          status: 'revoked',
          revoked_at: Time.current,
          revoked_reason: reason
        )
        
        # Remove from GitHub
        remove_from_github_repository(repository, access)
        
        # Track the revocation event
        track_access_event('access_revoked', repository, access, { reason: reason })
        
        success("Access revoked successfully", access: access)
      end
    rescue => e
      Rails.logger.error "Failed to revoke repository access: #{e.message}"
      failure("Failed to revoke access: #{e.message}")
    end
  end

  def bulk_grant_package_access(package, **options)
    return failure("User must connect GitHub account first") unless user.github_connected?
    
    results = []
    errors = []
    
    package.github_repositories.each do |repository|
      result = grant_repository_access(repository, **options.merge(
        access_source: 'package',
        purchase_reference: "package_#{package.id}"
      ))
      
      if result[:success]
        results << result[:access]
      else
        errors << "#{repository.name}: #{result[:error]}"
      end
    end
    
    if errors.empty?
      success("Package access granted successfully", accesses: results)
    else
      failure("Some repositories failed: #{errors.join(', ')}", accesses: results, errors: errors)
    end
  end

  def bulk_revoke_package_access(package, reason: nil)
    accesses = user.repository_accesses.joins(:github_repository)
                  .where(github_repositories: { id: package.github_repositories.pluck(:id) })
                  .where(status: 'active')
    
    results = []
    errors = []
    
    accesses.each do |access|
      result = revoke_repository_access(access.github_repository, reason: reason)
      
      if result[:success]
        results << access
      else
        errors << "#{access.github_repository.name}: #{result[:error]}"
      end
    end
    
    if errors.empty?
      success("Package access revoked successfully", accesses: results)
    else
      failure("Some repositories failed: #{errors.join(', ')}", accesses: results, errors: errors)
    end
  end

  def sync_github_access_status
    return failure("User must connect GitHub account first") unless user.github_connected?
    
    synced_count = 0
    errors = []
    
    user.repository_accesses.active.includes(:github_repository).each do |access|
      begin
        github_status = check_github_repository_access(access.github_repository)
        
        if github_status[:has_access] != (access.status == 'active')
          access.update!(status: github_status[:has_access] ? 'active' : 'expired')
          synced_count += 1
        end
        
        if github_status[:last_accessed]
          access.update!(last_accessed_at: github_status[:last_accessed])
        end
        
      rescue => e
        errors << "#{access.github_repository.name}: #{e.message}"
      end
    end
    
    if errors.empty?
      success("Synced #{synced_count} access records", synced_count: synced_count)
    else
      failure("Some syncs failed: #{errors.join(', ')}", synced_count: synced_count, errors: errors)
    end
  end

  def check_access_expiration
    expiring_accesses = user.repository_accesses.active
                           .where(expires_at: Time.current..7.days.from_now)
    
    expired_accesses = user.repository_accesses.active
                          .where('expires_at < ?', Time.current)
    
    # Auto-revoke expired accesses
    expired_accesses.each do |access|
      revoke_repository_access(access.github_repository, reason: 'Access expired')
    end
    
    # Send expiration warnings
    expiring_accesses.each do |access|
      GitHubAccessMailer.expiring_soon(access).deliver_later
    end
    
    {
      expiring_count: expiring_accesses.count,
      expired_count: expired_accesses.count
    }
  end

  def access_analytics
    accesses = user.repository_accesses.includes(:github_repository)
    
    {
      total_repositories: accesses.count,
      active_repositories: accesses.active.count,
      expired_repositories: accesses.where('expires_at < ?', Time.current).count,
      pending_invitations: accesses.where(status: 'pending').count,
      repositories_by_category: accesses.joins(:github_repository)
                                       .group('github_repositories.category')
                                       .count,
      access_sources: accesses.group(:access_source).count,
      total_access_count: accesses.sum(:access_count),
      last_access: accesses.maximum(:last_accessed_at),
      most_accessed_repository: most_accessed_repository
    }
  end

  private

  def create_or_update_access_record(repository, options)
    access_attrs = {
      access_level: options[:access_level] || 'read',
      expires_at: options[:expires_at],
      purchase_reference: options[:purchase_reference],
      polar_order_id: options[:polar_order_id],
      access_source: options[:access_source] || 'purchase',
      granted_at: Time.current,
      status: 'pending'
    }
    
    existing_access = user.repository_accesses.find_by(github_repository: repository)
    
    if existing_access
      existing_access.update!(access_attrs)
      existing_access
    else
      user.repository_accesses.create!(access_attrs.merge(github_repository: repository))
    end
  end

  def send_github_invitation(access)
    return unless github_client
    
    begin
      invitation_response = github_client.invite_to_repository(
        access.github_repository.full_name,
        user.github_username,
        permission: github_permission_level(access.access_level)
      )
      
      access.update!(
        github_invitation_id: invitation_response[:id],
        invitation_sent_at: Time.current,
        status: 'invited'
      )
      
      # Send notification email
      GitHubAccessMailer.invitation_sent(access).deliver_later
      
    rescue => e
      Rails.logger.error "Failed to send GitHub invitation: #{e.message}"
      access.update!(status: 'failed', notes: "Invitation failed: #{e.message}")
      raise
    end
  end

  def remove_from_github_repository(repository, access)
    return unless github_client && user.github_username
    
    begin
      github_client.remove_collaborator(repository.full_name, user.github_username)
      
      # Send notification email
      GitHubAccessMailer.access_revoked(access).deliver_later
      
    rescue => e
      Rails.logger.error "Failed to remove GitHub collaborator: #{e.message}"
      # Don't raise here as the local access has already been revoked
    end
  end

  def check_github_repository_access(repository)
    return { has_access: false } unless github_client
    
    begin
      collaboration = github_client.collaboration(repository.full_name, user.github_username)
      
      {
        has_access: collaboration[:state] == 'active',
        permission_level: collaboration[:permissions],
        last_accessed: collaboration[:last_accessed] # This may not be available in GitHub API
      }
    rescue => e
      Rails.logger.error "Failed to check GitHub access: #{e.message}"
      { has_access: false, error: e.message }
    end
  end

  def github_permission_level(access_level)
    case access_level
    when 'read'
      'pull'
    when 'write'
      'push'
    when 'admin'
      'admin'
    else
      'pull'
    end
  end

  def github_client
    @github_client ||= user.github_client || system_github_client
  end

  def system_github_client
    return nil unless ENV['GITHUB_ACCESS_TOKEN']
    @system_github_client ||= GitHubApiClient.new(ENV['GITHUB_ACCESS_TOKEN'])
  end

  def track_access_event(event_type, repository, access, additional_data = {})
    Analytics.track(
      user_id: user.id,
      event: event_type,
      properties: {
        repository_id: repository.id,
        repository_name: repository.full_name,
        access_level: access.access_level,
        access_source: access.access_source,
        **additional_data
      }
    )
  rescue => e
    Rails.logger.error "Failed to track access event: #{e.message}"
  end

  def most_accessed_repository
    user.repository_accesses.order(access_count: :desc).first&.github_repository
  end

  def success(message, **data)
    { success: true, message: message, **data }
  end

  def failure(message, **data)
    { success: false, error: message, **data }
  end
end