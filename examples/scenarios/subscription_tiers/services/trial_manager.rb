# frozen_string_literal: true

class TrialManager
  include ActiveModel::Model

  def self.check_expiring_trials
    new.check_expiring_trials
  end

  def self.process_expired_trials  
    new.process_expired_trials
  end

  def self.send_trial_notifications
    new.send_trial_notifications
  end

  def check_expiring_trials
    # Send notifications for trials expiring in 7 days
    users_7_days = User.where(trial_ends_at: 7.days.from_now.beginning_of_day..7.days.from_now.end_of_day)
    users_7_days.find_each do |user|
      TrialMailer.expiring_in_7_days(user).deliver_later
    end

    # Send notifications for trials expiring in 1 day
    users_1_day = User.where(trial_ends_at: 1.day.from_now.beginning_of_day..1.day.from_now.end_of_day)
    users_1_day.find_each do |user|
      TrialMailer.expiring_tomorrow(user).deliver_later
    end

    # Send notifications for trials expiring today
    users_today = User.where(trial_ends_at: Time.current.beginning_of_day..Time.current.end_of_day)
    users_today.find_each do |user|
      TrialMailer.expiring_today(user).deliver_later
    end
  end

  def process_expired_trials
    expired_users = User.trial_expired.where(current_tier: ['trial', 'pro'])
    
    expired_users.find_each do |user|
      # Only downgrade if they don't have an active subscription
      next if user.subscription_active?
      
      Rails.logger.info "Processing expired trial for user #{user.id}"
      
      # Downgrade to free tier
      user.update!(current_tier: 'free')
      
      # Update usage quota to free limits
      user.usage_quota&.update_quota_for_tier('free')
      
      # Send expired notification
      TrialMailer.trial_expired(user).deliver_later
      
      # Create follow-up sequence
      schedule_follow_up_emails(user)
    end
  end

  def extend_trial(user, days)
    return false unless user.trial_active?
    
    new_end_date = user.trial_ends_at + days.days
    user.update!(trial_ends_at: new_end_date)
    
    Rails.logger.info "Extended trial for user #{user.id} by #{days} days to #{new_end_date}"
    true
  end

  def convert_trial_to_subscription(user, subscription_data)
    return false unless user.trial_active?
    
    User.transaction do
      # Create subscription record
      subscription = user.subscriptions.create!(
        polar_subscription_id: subscription_data['id'],
        polar_product_id: subscription_data['product_id'],
        tier: determine_tier_from_product(subscription_data['product_id']),
        status: subscription_data['status'],
        amount: subscription_data['amount'] / 100.0, # Convert from cents
        currency: subscription_data['currency'],
        billing_interval: subscription_data['recurring']['interval'],
        current_period_start: Time.parse(subscription_data['current_period_start']),
        current_period_end: Time.parse(subscription_data['current_period_end']),
        trial_start: user.trial_started_at,
        trial_end: Time.parse(subscription_data['trial_end']) if subscription_data['trial_end']
      )

      # Update user tier
      user.update!(current_tier: subscription.tier)
      
      # Update usage quota
      user.usage_quota&.update_quota_for_tier(subscription.tier)
      
      Rails.logger.info "Converted trial to subscription for user #{user.id}, tier: #{subscription.tier}"
      
      # Send welcome email
      SubscriptionMailer.welcome_paid_user(user, subscription).deliver_later
      
      subscription
    end
  rescue => e
    Rails.logger.error "Failed to convert trial for user #{user.id}: #{e.message}"
    false
  end

  def restart_trial(user, tier = 'pro')
    return false if user.trial_active?
    return false if user.subscription_active?
    
    # Only allow restarting trial once per user (add a field to track this if needed)
    return false if user.trials_used&.positive?
    
    user.update!(
      trial_started_at: Time.current,
      trial_ends_at: 30.days.from_now,
      current_tier: tier,
      trials_used: (user.trials_used || 0) + 1
    )
    
    # Reset usage quota for new trial
    user.usage_quota&.update_quota_for_tier(tier)
    
    Rails.logger.info "Restarted trial for user #{user.id} with tier #{tier}"
    true
  end

  def trial_usage_summary(user)
    return {} unless user.trial_active?
    
    {
      days_remaining: user.trial_days_remaining,
      tier: user.current_tier,
      started_at: user.trial_started_at,
      ends_at: user.trial_ends_at,
      usage: user.usage_quota&.usage_summary || [],
      conversion_opportunities: identify_conversion_opportunities(user)
    }
  end

  private

  def schedule_follow_up_emails(user)
    # Schedule follow-up emails to encourage subscription
    TrialMailer.follow_up_day_1(user).deliver_later(wait: 1.day)
    TrialMailer.follow_up_day_3(user).deliver_later(wait: 3.days)
    TrialMailer.follow_up_day_7(user).deliver_later(wait: 7.days)
    TrialMailer.final_offer(user).deliver_later(wait: 14.days)
  end

  def determine_tier_from_product(product_id)
    # Map Polar product IDs to tier names
    tier_definitions = TierDefinition.all
    tier_definitions.each do |tier_def|
      return tier_def.name if [tier_def.polar_monthly_product_id, tier_def.polar_yearly_product_id].include?(product_id)
    end
    
    'starter' # Default fallback
  end

  def identify_conversion_opportunities(user)
    opportunities = []
    quota = user.usage_quota
    
    return opportunities unless quota
    
    # High usage indicates engagement
    opportunities << 'high_usage' if quota.usage_percentage('projects') > 70
    opportunities << 'team_collaboration' if quota.team_members_used > 1
    opportunities << 'storage_intensive' if quota.usage_percentage('storage_bytes') > 60
    opportunities << 'api_heavy' if quota.usage_percentage('api_calls') > 50
    
    # Feature access attempts
    opportunities << 'advanced_features' if user.feature_access_attempts&.any?
    
    opportunities
  end
end