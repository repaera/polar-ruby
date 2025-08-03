# frozen_string_literal: true

class User < ApplicationRecord
  has_many :subscriptions, dependent: :destroy
  has_one :active_subscription, -> { where(status: ['active', 'trialing']) }, class_name: 'Subscription'
  has_one :usage_quota, dependent: :destroy

  enum current_tier: {
    trial: 'trial',
    free: 'free', 
    starter: 'starter',
    pro: 'pro',
    enterprise: 'enterprise'
  }

  after_create :start_trial_period
  after_create :create_usage_quota

  scope :trial_expiring_soon, -> { where(trial_ends_at: 1.day.from_now..3.days.from_now) }
  scope :trial_expired, -> { where('trial_ends_at < ?', Time.current) }

  def trial_active?
    trial_ends_at.present? && trial_ends_at > Time.current
  end

  def trial_expired?
    trial_ends_at.present? && trial_ends_at <= Time.current
  end

  def trial_days_remaining
    return 0 unless trial_active?
    ((trial_ends_at - Time.current) / 1.day).ceil
  end

  def subscription_active?
    active_subscription&.active?
  end

  def effective_tier
    return current_tier if trial_active? || subscription_active?
    'free'
  end

  def tier_definition
    @tier_definition ||= TierDefinition.find_by(name: effective_tier)
  end

  def can_access_feature?(feature_name)
    tier_definition&.features&.dig(feature_name.to_s) || false
  end

  def usage_quota_for(resource)
    usage_quota&.send("#{resource}_limit") || 0
  end

  def usage_count_for(resource)
    usage_quota&.send("#{resource}_used") || 0
  end

  def usage_percentage_for(resource)
    limit = usage_quota_for(resource)
    return 0 if limit.zero?
    
    used = usage_count_for(resource)
    (used.to_f / limit * 100).round(1)
  end

  def at_usage_limit?(resource)
    usage_count_for(resource) >= usage_quota_for(resource)
  end

  def polar_customer
    return @polar_customer if defined?(@polar_customer)
    
    @polar_customer = if polar_customer_id.present?
      begin
        Polar.client.customers.retrieve(polar_customer_id)
      rescue Polar::NotFoundError
        create_polar_customer
      end
    else
      create_polar_customer
    end
  end

  def create_checkout_session(tier_name, billing_interval = 'monthly')
    tier_def = TierDefinition.find_by!(name: tier_name)
    product_id = billing_interval == 'yearly' ? tier_def.polar_yearly_product_id : tier_def.polar_monthly_product_id
    
    Polar.client.checkouts.create({
      product_id: product_id,
      customer: {
        email: email,
        external_id: id.to_s
      },
      success_url: Rails.application.routes.url_helpers.subscription_success_url(host: Rails.application.config.app_host),
      cancel_url: Rails.application.routes.url_helpers.pricing_url(host: Rails.application.config.app_host),
      metadata: {
        user_id: id,
        tier: tier_name,
        billing_interval: billing_interval
      }
    })
  end

  def customer_portal_url
    return nil unless polar_customer_id

    begin
      session = Polar.client.customers.portal_session(
        polar_customer_id,
        return_url: Rails.application.routes.url_helpers.account_url(host: Rails.application.config.app_host)
      )
      session['url']
    rescue Polar::APIError => e
      Rails.logger.error "Failed to create portal session: #{e.message}"
      nil
    end
  end

  private

  def start_trial_period
    self.update_columns(
      trial_started_at: Time.current,
      trial_ends_at: 30.days.from_now,
      current_tier: 'pro' # Start trial with Pro features
    )
  end

  def create_usage_quota
    UsageQuota.create!(
      user: self,
      tier: effective_tier,
      **TierDefinition.quota_limits_for(effective_tier)
    )
  end

  def create_polar_customer
    customer = Polar.client.customers.create({
      email: email,
      external_id: id.to_s,
      name: [first_name, last_name].compact.join(' ').presence || email.split('@').first,
      metadata: {
        created_via: 'rails_app',
        user_id: id,
        trial_ends_at: trial_ends_at&.iso8601
      }
    })

    update_column(:polar_customer_id, customer['id'])
    customer
  rescue Polar::APIError => e
    Rails.logger.error "Failed to create Polar customer: #{e.message}"
    nil
  end
end