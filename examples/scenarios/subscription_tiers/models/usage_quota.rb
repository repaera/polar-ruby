# frozen_string_literal: true

class UsageQuota < ApplicationRecord
  belongs_to :user

  enum tier: {
    free: 'free',
    trial: 'trial',
    starter: 'starter', 
    pro: 'pro',
    enterprise: 'enterprise'
  }

  validates :tier, presence: true

  before_save :set_period_dates, if: :will_save_change_to_tier?

  QUOTA_FIELDS = %w[projects team_members storage_bytes api_calls].freeze

  def self.quota_limits_for(tier_name)
    tier_def = TierDefinition.find_by(name: tier_name)
    return default_free_limits unless tier_def

    {
      projects_limit: tier_def.projects_limit,
      team_members_limit: tier_def.team_members_limit,
      storage_limit_bytes: tier_def.storage_limit_bytes,
      api_calls_limit: tier_def.api_calls_limit,
      features_enabled: tier_def.features
    }
  end

  def self.default_free_limits
    {
      projects_limit: 1,
      team_members_limit: 1,
      storage_limit_bytes: 100.megabytes,
      api_calls_limit: 100,
      features_enabled: {
        'advanced_analytics' => false,
        'priority_support' => false,
        'custom_integrations' => false,
        'team_collaboration' => false,
        'export_data' => false
      }
    }
  end

  def update_quota_for_tier(new_tier)
    limits = self.class.quota_limits_for(new_tier)
    
    update!(
      tier: new_tier,
      **limits
    )
    
    reset_period_usage if should_reset_usage_for_tier_change?(new_tier)
  end

  def increment_usage!(resource, amount = 1)
    field_name = "#{resource}_used"
    return false unless respond_to?(field_name)

    current_usage = send(field_name) || 0
    new_usage = current_usage + amount
    
    # Check if this would exceed the limit
    limit = send("#{resource}_limit")
    return false if limit && new_usage > limit

    update_column(field_name, new_usage)
    true
  end

  def decrement_usage!(resource, amount = 1)
    field_name = "#{resource}_used"
    return false unless respond_to?(field_name)

    current_usage = send(field_name) || 0
    new_usage = [current_usage - amount, 0].max
    
    update_column(field_name, new_usage)
    true
  end

  def usage_percentage(resource)
    used = send("#{resource}_used") || 0
    limit = send("#{resource}_limit") || 0
    return 0 if limit.zero?
    
    (used.to_f / limit * 100).round(1)
  end

  def at_limit?(resource)
    used = send("#{resource}_used") || 0
    limit = send("#{resource}_limit") || 0
    used >= limit
  end

  def near_limit?(resource, threshold = 0.8)
    usage_percentage(resource) >= (threshold * 100)
  end

  def can_consume?(resource, amount = 1)
    used = send("#{resource}_used") || 0
    limit = send("#{resource}_limit") || 0
    return true if limit.zero? # Unlimited
    
    (used + amount) <= limit
  end

  def remaining_quota(resource)
    used = send("#{resource}_used") || 0
    limit = send("#{resource}_limit") || 0
    return Float::INFINITY if limit.zero? # Unlimited
    
    [limit - used, 0].max
  end

  def feature_enabled?(feature_name)
    features_enabled&.dig(feature_name.to_s) || false
  end

  def reset_period_usage
    QUOTA_FIELDS.each do |field|
      update_column("#{field}_used", 0)
    end
    
    update_columns(
      current_period_start: Date.current.beginning_of_month,
      current_period_end: Date.current.end_of_month
    )
  end

  def days_until_reset
    return 0 unless current_period_end
    (current_period_end - Date.current).to_i
  end

  def usage_summary
    QUOTA_FIELDS.map do |resource|
      {
        resource: resource,
        used: send("#{resource}_used") || 0,
        limit: send("#{resource}_limit") || 0,
        percentage: usage_percentage(resource),
        remaining: remaining_quota(resource)
      }
    end
  end

  def over_limit_resources
    QUOTA_FIELDS.select { |resource| at_limit?(resource) }
  end

  def warning_resources(threshold = 0.8)
    QUOTA_FIELDS.select { |resource| near_limit?(resource, threshold) }
  end

  private

  def set_period_dates
    self.current_period_start = Date.current.beginning_of_month
    self.current_period_end = Date.current.end_of_month
  end

  def should_reset_usage_for_tier_change?(new_tier)
    # Reset usage when upgrading to give immediate benefit
    tier_levels = { 'free' => 0, 'starter' => 1, 'pro' => 2, 'enterprise' => 3 }
    old_level = tier_levels[tier] || 0
    new_level = tier_levels[new_tier.to_s] || 0
    
    new_level > old_level
  end
end