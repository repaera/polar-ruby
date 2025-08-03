# frozen_string_literal: true

class PolarWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def subscription_webhook
    payload = request.body.read
    signature = request.headers['Polar-Signature']
    
    # Verify webhook signature (implement according to Polar docs)
    unless verify_webhook_signature(payload, signature)
      head :unauthorized
      return
    end
    
    event = JSON.parse(payload)
    
    case event['type']
    when 'subscription.created'
      handle_subscription_created(event['data'])
    when 'subscription.updated'
      handle_subscription_updated(event['data'])
    when 'subscription.cancelled'
      handle_subscription_cancelled(event['data'])
    when 'subscription.resumed'
      handle_subscription_resumed(event['data'])
    when 'order.completed'
      handle_order_completed(event['data'])
    when 'customer.updated'
      handle_customer_updated(event['data'])
    else
      Rails.logger.info "Unhandled webhook event: #{event['type']}"
    end
    
    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error "Invalid JSON in webhook: #{e.message}"
    head :bad_request
  rescue => e
    Rails.logger.error "Webhook processing error: #{e.message}"
    head :internal_server_error
  end

  private

  def handle_subscription_created(subscription_data)
    user = find_user_by_customer_id(subscription_data['customer_id'])
    return unless user

    Rails.logger.info "Processing subscription created for user #{user.id}"
    
    User.transaction do
      # Create subscription record
      subscription = user.subscriptions.create!(
        polar_subscription_id: subscription_data['id'],
        polar_product_id: subscription_data['product_id'],
        tier: determine_tier_from_product(subscription_data['product_id']),
        status: subscription_data['status'],
        amount: (subscription_data['amount'] || 0) / 100.0, # Convert from cents
        currency: subscription_data['currency'] || 'USD',
        billing_interval: subscription_data['recurring']&.dig('interval') || 'monthly',
        current_period_start: parse_timestamp(subscription_data['current_period_start']),
        current_period_end: parse_timestamp(subscription_data['current_period_end']),
        trial_start: user.trial_started_at,
        trial_end: parse_timestamp(subscription_data['trial_end']),
        metadata: subscription_data['metadata'] || {}
      )

      # Update user tier and end trial
      user.update!(
        current_tier: subscription.tier,
        trial_ends_at: nil # End trial when subscription starts
      )
      
      # Update usage quota for new tier
      user.usage_quota&.update_quota_for_tier(subscription.tier)
      
      # Send welcome email
      SubscriptionMailer.subscription_activated(user, subscription).deliver_later
      
      # Track conversion event
      track_subscription_event(user, 'subscription_created', subscription_data)
    end
  end

  def handle_subscription_updated(subscription_data)
    subscription = find_subscription(subscription_data['id'])
    return unless subscription

    Rails.logger.info "Processing subscription updated: #{subscription.id}"
    
    old_tier = subscription.tier
    new_tier = determine_tier_from_product(subscription_data['product_id'])
    
    subscription.update!(
      status: subscription_data['status'],
      amount: (subscription_data['amount'] || 0) / 100.0,
      current_period_start: parse_timestamp(subscription_data['current_period_start']),
      current_period_end: parse_timestamp(subscription_data['current_period_end']),
      tier: new_tier,
      polar_product_id: subscription_data['product_id'],
      cancel_at_period_end: subscription_data['cancel_at_period_end'] || false,
      metadata: subscription_data['metadata'] || {}
    )
    
    # Update user tier if changed
    if old_tier != new_tier
      subscription.user.update!(current_tier: new_tier)
      subscription.user.usage_quota&.update_quota_for_tier(new_tier)
      
      # Send tier change notification
      SubscriptionMailer.tier_changed(subscription.user, subscription, old_tier, new_tier).deliver_later
    end
    
    # Handle status changes
    case subscription_data['status']
    when 'active'
      handle_subscription_activated(subscription)
    when 'past_due'
      handle_subscription_past_due(subscription)
    when 'cancelled'
      handle_subscription_cancelled_status(subscription)
    end
    
    track_subscription_event(subscription.user, 'subscription_updated', subscription_data)
  end

  def handle_subscription_cancelled(subscription_data)
    subscription = find_subscription(subscription_data['id'])
    return unless subscription

    Rails.logger.info "Processing subscription cancelled: #{subscription.id}"
    
    subscription.update!(
      status: 'cancelled',
      cancelled_at: Time.current,
      cancel_at_period_end: subscription_data['cancel_at_period_end'] || false
    )
    
    # If immediate cancellation, downgrade user now
    unless subscription.cancel_at_period_end?
      subscription.user.update!(current_tier: 'free')
      subscription.user.usage_quota&.update_quota_for_tier('free')
    end
    
    # Send cancellation confirmation
    SubscriptionMailer.subscription_cancelled(subscription.user, subscription).deliver_later
    
    # Schedule follow-up emails for re-engagement
    schedule_cancellation_follow_up(subscription.user)
    
    track_subscription_event(subscription.user, 'subscription_cancelled', subscription_data)
  end

  def handle_subscription_resumed(subscription_data)
    subscription = find_subscription(subscription_data['id'])
    return unless subscription

    Rails.logger.info "Processing subscription resumed: #{subscription.id}"
    
    subscription.update!(
      status: 'active',
      cancelled_at: nil,
      cancel_at_period_end: false
    )
    
    # Reactivate user tier
    subscription.user.update!(current_tier: subscription.tier)
    subscription.user.usage_quota&.update_quota_for_tier(subscription.tier)
    
    # Send reactivation confirmation
    SubscriptionMailer.subscription_reactivated(subscription.user, subscription).deliver_later
    
    track_subscription_event(subscription.user, 'subscription_resumed', subscription_data)
  end

  def handle_order_completed(order_data)
    # Handle one-time purchases or subscription upgrades
    user = find_user_by_customer_id(order_data['customer_id'])
    return unless user

    Rails.logger.info "Processing order completed for user #{user.id}"
    
    # If this is a subscription order, it will be handled by subscription.created
    # Here we handle one-time purchases or credits
    
    if order_data['metadata']&.dig('type') == 'credits'
      handle_credit_purchase(user, order_data)
    end
    
    track_subscription_event(user, 'order_completed', order_data)
  end

  def handle_customer_updated(customer_data)
    user = find_user_by_customer_id(customer_data['id'])
    return unless user

    # Update user information from customer data
    user.update!(
      email: customer_data['email'] || user.email,
      # Update other fields as needed
    )
  end

  # Helper methods for subscription status changes
  def handle_subscription_activated(subscription)
    # Subscription became active (e.g., after trial or payment retry)
    subscription.user.update!(current_tier: subscription.tier)
    subscription.user.usage_quota&.update_quota_for_tier(subscription.tier)
  end

  def handle_subscription_past_due(subscription)
    # Send payment failed notifications
    SubscriptionMailer.payment_failed(subscription.user, subscription).deliver_later
    
    # Schedule reminder emails
    SubscriptionMailer.payment_retry_reminder(subscription.user, subscription).deliver_later(wait: 3.days)
  end

  def handle_subscription_cancelled_status(subscription)
    # Subscription was cancelled (different from cancellation webhook)
    unless subscription.cancel_at_period_end?
      subscription.user.update!(current_tier: 'free')
      subscription.user.usage_quota&.update_quota_for_tier('free')
    end
  end

  def handle_credit_purchase(user, order_data)
    credits_amount = order_data['metadata']&.dig('credits_amount')&.to_f || 0
    package_id = order_data['metadata']&.dig('package_id')
    
    return unless credits_amount > 0
    
    package = CreditPackage.find_by(id: package_id) if package_id
    
    user.add_credits!(
      credits_amount,
      package: package,
      polar_order_id: order_data['id'],
      description: "Purchased #{credits_amount} credits"
    )
  end

  # Utility methods
  def find_user_by_customer_id(customer_id)
    User.find_by(polar_customer_id: customer_id)
  end

  def find_subscription(polar_subscription_id)
    Subscription.find_by(polar_subscription_id: polar_subscription_id)
  end

  def determine_tier_from_product(product_id)
    # Map Polar product IDs to tier names
    tier_definitions = TierDefinition.all
    tier_definitions.each do |tier_def|
      return tier_def.name if [tier_def.polar_monthly_product_id, tier_def.polar_yearly_product_id].include?(product_id)
    end
    
    'starter' # Default fallback
  end

  def parse_timestamp(timestamp)
    return nil unless timestamp
    Time.parse(timestamp)
  rescue ArgumentError
    nil
  end

  def schedule_cancellation_follow_up(user)
    # Schedule re-engagement email sequence
    SubscriptionMailer.cancellation_follow_up_1(user).deliver_later(wait: 1.day)
    SubscriptionMailer.cancellation_follow_up_2(user).deliver_later(wait: 3.days)
    SubscriptionMailer.win_back_offer(user).deliver_later(wait: 7.days)
  end

  def track_subscription_event(user, event_type, event_data)
    Analytics.track(
      user_id: user.id,
      event: event_type,
      properties: {
        subscription_id: event_data['id'],
        product_id: event_data['product_id'],
        amount: event_data['amount'],
        currency: event_data['currency'],
        status: event_data['status'],
        **event_data['metadata']&.symbolize_keys || {}
      }
    )
  rescue => e
    Rails.logger.error "Failed to track subscription event: #{e.message}"
  end

  def verify_webhook_signature(payload, signature)
    # Implement signature verification according to Polar's documentation
    # This is a placeholder - implement actual verification
    true
  end
end