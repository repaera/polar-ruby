# frozen_string_literal: true

class PricingController < ApplicationController
  def index
    @tier_definitions = TierDefinition.active.ordered
    @current_user_tier = current_user&.effective_tier
    @trial_info = trial_information if user_signed_in?
    @billing_interval = params[:billing_interval] || 'monthly'
  end

  def compare
    @tier_definitions = TierDefinition.active.ordered
    @features = compile_all_features
    @current_user_tier = current_user&.effective_tier if user_signed_in?
  end

  def trial_status
    return render json: { error: 'Not authenticated' }, status: 401 unless user_signed_in?
    
    render json: {
      trial_active: current_user.trial_active?,
      trial_days_remaining: current_user.trial_days_remaining,
      current_tier: current_user.effective_tier,
      usage_summary: current_user.usage_quota&.usage_summary || []
    }
  end

  def upgrade_recommendations
    return render json: { error: 'Not authenticated' }, status: 401 unless user_signed_in?
    
    recommendations = generate_upgrade_recommendations
    
    render json: {
      current_tier: current_user.effective_tier,
      recommendations: recommendations,
      usage_warnings: current_user.usage_quota&.warning_resources || []
    }
  end

  private

  def trial_information
    return nil unless current_user&.trial_active?
    
    {
      days_remaining: current_user.trial_days_remaining,
      tier: current_user.current_tier,
      expires_at: current_user.trial_ends_at,
      usage_summary: current_user.usage_quota&.usage_summary || []
    }
  end

  def compile_all_features
    all_features = TierDefinition.active.map(&:features).compact
    feature_names = all_features.flat_map(&:keys).uniq.sort
    
    feature_names.map do |feature_name|
      {
        name: feature_name,
        display_name: feature_name.humanize,
        tiers: @tier_definitions.map do |tier|
          {
            tier: tier.name,
            enabled: tier.feature_enabled?(feature_name)
          }
        end
      }
    end
  end

  def generate_upgrade_recommendations
    return [] unless current_user
    
    recommendations = []
    quota = current_user.usage_quota
    current_tier_def = current_user.tier_definition
    
    return recommendations unless quota && current_tier_def
    
    # Check for quota-based recommendations
    if quota.usage_percentage('projects') > 80
      better_tier = find_tier_with_higher_limit('projects_limit', quota.projects_used)
      if better_tier
        recommendations << {
          reason: 'High project usage',
          suggestion: "Upgrade to #{better_tier.display_name} for more projects",
          tier: better_tier.name,
          urgency: 'high'
        }
      end
    end
    
    if quota.usage_percentage('storage_bytes') > 80
      better_tier = find_tier_with_higher_limit('storage_limit_bytes', quota.storage_used_bytes)
      if better_tier
        recommendations << {
          reason: 'Storage nearly full',
          suggestion: "Upgrade to #{better_tier.display_name} for more storage",
          tier: better_tier.name,
          urgency: 'high'
        }
      end
    end
    
    # Check for feature-based recommendations
    if attempted_premium_features?
      premium_tier = TierDefinition.active.ordered.find { |t| t.feature_enabled?('advanced_analytics') }
      if premium_tier && premium_tier.name != current_user.effective_tier
        recommendations << {
          reason: 'Attempted to use premium features',
          suggestion: "Upgrade to #{premium_tier.display_name} for advanced features",
          tier: premium_tier.name,
          urgency: 'medium'
        }
      end
    end
    
    recommendations
  end

  def find_tier_with_higher_limit(limit_field, current_usage)
    current_tier_level = tier_hierarchy_level(current_user.effective_tier)
    
    TierDefinition.active.ordered.find do |tier|
      tier_level = tier_hierarchy_level(tier.name)
      tier_level > current_tier_level && 
        (tier.send(limit_field).nil? || tier.send(limit_field) > current_usage * 1.5)
    end
  end

  def tier_hierarchy_level(tier_name)
    hierarchy = { 'free' => 0, 'starter' => 1, 'pro' => 2, 'enterprise' => 3 }
    hierarchy[tier_name] || 0
  end

  def attempted_premium_features?
    # This would be tracked in your application when users try to access premium features
    # For now, return false as a placeholder
    false
  end
end