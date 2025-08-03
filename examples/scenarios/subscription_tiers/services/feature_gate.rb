# frozen_string_literal: true

class FeatureGate
  include ActiveModel::Model
  
  attr_accessor :user, :feature, :resource, :amount

  def initialize(user:, feature: nil, resource: nil, amount: 1)
    @user = user
    @feature = feature
    @resource = resource
    @amount = amount
  end

  def self.can_access?(user:, feature:)
    new(user: user, feature: feature).can_access_feature?
  end

  def self.can_consume?(user:, resource:, amount: 1)
    new(user: user, resource: resource, amount: amount).can_consume_resource?
  end

  def self.enforce!(user:, feature: nil, resource: nil, amount: 1)
    gate = new(user: user, feature: feature, resource: resource, amount: amount)
    
    if feature
      raise FeatureNotAvailableError.new(feature) unless gate.can_access_feature?
    end
    
    if resource
      raise QuotaExceededError.new(resource) unless gate.can_consume_resource?
    end
    
    true
  end

  def can_access_feature?
    return true unless feature
    
    # Always allow during active trial or subscription
    return true if user.trial_active? || user.subscription_active?
    
    # Check tier definition for feature access
    tier_def = user.tier_definition
    return false unless tier_def
    
    tier_def.feature_enabled?(feature)
  end

  def can_consume_resource?
    return true unless resource
    return true unless user.usage_quota
    
    user.usage_quota.can_consume?(resource, amount)
  end

  def consume_resource!
    return false unless can_consume_resource?
    return true unless resource && user.usage_quota
    
    user.usage_quota.increment_usage!(resource, amount)
  end

  def feature_upgrade_required?
    !can_access_feature?
  end

  def quota_upgrade_required?
    !can_consume_resource?
  end

  def suggested_tier_for_feature
    return user.effective_tier if can_access_feature?
    
    TierDefinition.active.ordered.find do |tier_def|
      tier_def.feature_enabled?(feature)
    end&.name
  end

  def suggested_tier_for_quota
    return user.effective_tier if can_consume_resource?
    
    current_usage = user.usage_quota&.send("#{resource}_used") || 0
    required_limit = current_usage + amount
    
    TierDefinition.active.ordered.find do |tier_def|
      limit = tier_def.send("#{resource}_limit")
      limit.nil? || limit >= required_limit
    end&.name
  end

  def upgrade_message_for_feature
    suggested_tier = suggested_tier_for_feature
    return nil unless suggested_tier
    
    tier_def = TierDefinition.find_by(name: suggested_tier)
    "This feature requires #{tier_def.display_name} plan. Upgrade for $#{tier_def.monthly_price}/month."
  end

  def upgrade_message_for_quota
    suggested_tier = suggested_tier_for_quota
    return nil unless suggested_tier
    
    tier_def = TierDefinition.find_by(name: suggested_tier)
    current_limit = user.usage_quota_for(resource)
    new_limit = tier_def.send("#{resource}_limit")
    
    "You've reached your #{resource.humanize.downcase} limit (#{current_limit}). " \
    "Upgrade to #{tier_def.display_name} for #{new_limit.zero? ? 'unlimited' : new_limit} #{resource.humanize.downcase}."
  end

  def self.middleware
    @middleware ||= FeatureGateMiddleware.new
  end

  class FeatureGateMiddleware
    def feature_required(feature_name)
      lambda do |controller|
        user = controller.current_user
        return controller.redirect_to_upgrade(feature: feature_name) unless FeatureGate.can_access?(user: user, feature: feature_name)
      end
    end

    def quota_required(resource, amount = 1)
      lambda do |controller|
        user = controller.current_user
        return controller.redirect_to_upgrade(resource: resource) unless FeatureGate.can_consume?(user: user, resource: resource, amount: amount)
      end
    end
  end

  # Helper methods for common features
  def self.can_create_project?(user)
    can_consume?(user: user, resource: 'projects')
  end

  def self.can_invite_team_member?(user)
    can_consume?(user: user, resource: 'team_members')
  end

  def self.can_upload_file?(user, file_size)
    can_consume?(user: user, resource: 'storage_bytes', amount: file_size)
  end

  def self.can_make_api_call?(user)
    can_consume?(user: user, resource: 'api_calls')
  end

  def self.can_access_analytics?(user)
    can_access?(user: user, feature: 'advanced_analytics')
  end

  def self.can_access_priority_support?(user)
    can_access?(user: user, feature: 'priority_support')
  end

  def self.can_use_integrations?(user)
    can_access?(user: user, feature: 'custom_integrations')
  end

  def self.can_export_data?(user)
    can_access?(user: user, feature: 'export_data')
  end
end

# Custom exception classes
class FeatureNotAvailableError < StandardError
  attr_reader :feature

  def initialize(feature)
    @feature = feature
    super("Feature '#{feature}' is not available on your current plan")
  end
end

class QuotaExceededError < StandardError
  attr_reader :resource

  def initialize(resource)
    @resource = resource
    super("You have exceeded your #{resource.humanize.downcase} quota")
  end
end