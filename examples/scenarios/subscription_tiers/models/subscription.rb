# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :user

  enum status: {
    incomplete: 'incomplete',
    incomplete_expired: 'incomplete_expired',
    trialing: 'trialing',
    active: 'active',
    past_due: 'past_due',
    canceled: 'canceled',
    unpaid: 'unpaid'
  }

  enum tier: {
    starter: 'starter',
    pro: 'pro', 
    enterprise: 'enterprise'
  }

  enum billing_interval: {
    monthly: 'monthly',
    yearly: 'yearly'
  }

  validates :polar_subscription_id, presence: true, uniqueness: true
  validates :polar_product_id, presence: true
  validates :tier, presence: true
  validates :status, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }

  scope :active_subscriptions, -> { where(status: ['active', 'trialing']) }
  scope :expiring_soon, -> { where(current_period_end: Time.current..7.days.from_now) }

  after_update :sync_user_tier, if: :saved_change_to_status?
  after_update :update_usage_quota, if: :saved_change_to_tier?

  def active?
    %w[active trialing].include?(status)
  end

  def in_trial?
    status == 'trialing'
  end

  def trial_days_remaining
    return 0 unless in_trial? && trial_end
    ((trial_end - Time.current) / 1.day).ceil.clamp(0, Float::INFINITY)
  end

  def days_until_renewal
    return 0 unless current_period_end
    ((current_period_end - Time.current) / 1.day).ceil.clamp(0, Float::INFINITY)
  end

  def polar_subscription
    @polar_subscription ||= Polar.client.subscriptions.retrieve(polar_subscription_id)
  rescue Polar::NotFoundError
    nil
  end

  def cancel!(at_period_end: true)
    result = Polar.client.subscriptions.cancel(polar_subscription_id, cancel_at_period_end: at_period_end)
    
    update!(
      status: result['status'],
      cancelled_at: Time.current,
      cancel_at_period_end: at_period_end
    )
    
    # If immediate cancellation, downgrade user
    unless at_period_end
      user.update!(current_tier: 'free')
      user.usage_quota.update_quota_for_tier('free')
    end

    result
  rescue Polar::APIError => e
    errors.add(:base, "Failed to cancel subscription: #{e.message}")
    false
  end

  def reactivate!
    result = Polar.client.subscriptions.reactivate(polar_subscription_id)
    
    update!(
      status: result['status'],
      cancelled_at: nil,
      cancel_at_period_end: false
    )
    
    # Reactivate user tier
    user.update!(current_tier: tier)
    user.usage_quota.update_quota_for_tier(tier)

    result
  rescue Polar::APIError => e
    errors.add(:base, "Failed to reactivate subscription: #{e.message}")
    false
  end

  def change_tier!(new_tier, billing_interval = self.billing_interval)
    new_tier_def = TierDefinition.find_by!(name: new_tier)
    product_id = billing_interval == 'yearly' ? new_tier_def.polar_yearly_product_id : new_tier_def.polar_monthly_product_id

    result = Polar.client.subscriptions.change_product(
      polar_subscription_id,
      product_id
    )
    
    update!(
      tier: new_tier,
      polar_product_id: product_id,
      amount: billing_interval == 'yearly' ? new_tier_def.yearly_price : new_tier_def.monthly_price,
      billing_interval: billing_interval,
      status: result['status']
    )
    
    # Update user tier and quotas
    user.update!(current_tier: new_tier)
    user.usage_quota.update_quota_for_tier(new_tier)

    result
  rescue Polar::APIError => e
    errors.add(:base, "Failed to change subscription: #{e.message}")
    false
  end

  def next_billing_amount
    return amount unless cancel_at_period_end
    0
  end

  def prorate_upgrade_cost(new_tier)
    # Calculate prorated cost for immediate upgrade
    new_tier_def = TierDefinition.find_by(name: new_tier)
    return 0 unless new_tier_def

    days_remaining = days_until_renewal
    total_days = billing_interval == 'yearly' ? 365 : 30
    
    current_daily_rate = amount / total_days
    new_daily_rate = (billing_interval == 'yearly' ? new_tier_def.yearly_price : new_tier_def.monthly_price) / total_days
    
    (new_daily_rate - current_daily_rate) * days_remaining
  end

  private

  def sync_user_tier
    case status
    when 'active', 'trialing'
      user.update!(current_tier: tier)
    when 'canceled', 'past_due', 'unpaid'
      # Only downgrade if not in grace period
      user.update!(current_tier: 'free') unless cancel_at_period_end && current_period_end > Time.current
    end
  end

  def update_usage_quota
    user.usage_quota&.update_quota_for_tier(tier)
  end
end