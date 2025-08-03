# frozen_string_literal: true

class TierDefinition < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :display_name, presence: true
  validates :monthly_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :yearly_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :monthly_price) }

  def self.quota_limits_for(tier_name)
    tier = find_by(name: tier_name)
    return UsageQuota.default_free_limits unless tier

    {
      projects_limit: tier.projects_limit,
      team_members_limit: tier.team_members_limit, 
      storage_limit_bytes: tier.storage_limit_bytes,
      api_calls_limit: tier.api_calls_limit,
      features_enabled: tier.features
    }
  end

  def yearly_discount_percentage
    return 0 if monthly_price.zero?
    
    monthly_yearly_equivalent = monthly_price * 12
    discount_amount = monthly_yearly_equivalent - yearly_price
    (discount_amount / monthly_yearly_equivalent * 100).round
  end

  def feature_enabled?(feature_name)
    features&.dig(feature_name.to_s) || false
  end

  def storage_limit_human
    return 'Unlimited' if storage_limit_bytes.nil? || storage_limit_bytes.zero?
    
    if storage_limit_bytes >= 1.terabyte
      "#{(storage_limit_bytes / 1.terabyte).round(1)}TB"
    elsif storage_limit_bytes >= 1.gigabyte
      "#{(storage_limit_bytes / 1.gigabyte).round(1)}GB"
    elsif storage_limit_bytes >= 1.megabyte
      "#{(storage_limit_bytes / 1.megabyte).round(1)}MB"
    else
      "#{storage_limit_bytes} bytes"
    end
  end

  def api_calls_limit_human
    return 'Unlimited' if api_calls_limit.nil? || api_calls_limit.zero?
    
    if api_calls_limit >= 1_000_000
      "#{(api_calls_limit / 1_000_000.0).round(1)}M"
    elsif api_calls_limit >= 1_000
      "#{(api_calls_limit / 1_000.0).round(1)}K"
    else
      api_calls_limit.to_s
    end
  end

  def projects_limit_human
    return 'Unlimited' if projects_limit.nil? || projects_limit.zero?
    projects_limit.to_s
  end

  def team_members_limit_human
    return 'Unlimited' if team_members_limit.nil? || team_members_limit.zero?
    team_members_limit.to_s
  end

  def monthly_price_formatted
    return 'Free' if monthly_price.zero?
    "$#{monthly_price.to_i}"
  end

  def yearly_price_formatted
    return 'Free' if yearly_price.zero?
    "$#{yearly_price.to_i}"
  end

  def monthly_equivalent_price
    return 0 if yearly_price.zero?
    (yearly_price / 12).round(2)
  end

  def is_upgrade_from?(other_tier_name)
    other_tier = self.class.find_by(name: other_tier_name)
    return false unless other_tier
    
    monthly_price > other_tier.monthly_price
  end

  def is_downgrade_from?(other_tier_name)
    other_tier = self.class.find_by(name: other_tier_name)
    return false unless other_tier
    
    monthly_price < other_tier.monthly_price
  end

  # Define feature comparison methods
  def has_feature?(feature_name)
    features&.dig(feature_name.to_s) == true
  end

  def feature_list
    return [] unless features.is_a?(Hash)
    
    features.select { |_, enabled| enabled }.keys
  end

  def missing_features_compared_to(other_tier_name)
    other_tier = self.class.find_by(name: other_tier_name)
    return [] unless other_tier
    
    other_features = other_tier.feature_list
    current_features = feature_list
    
    other_features - current_features
  end

  def additional_features_compared_to(other_tier_name)
    other_tier = self.class.find_by(name: other_tier_name)
    return feature_list unless other_tier
    
    other_features = other_tier.feature_list
    current_features = feature_list
    
    current_features - other_features
  end
end