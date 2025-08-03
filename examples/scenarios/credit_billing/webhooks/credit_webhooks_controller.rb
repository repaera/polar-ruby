# frozen_string_literal: true

class CreditWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def polar_webhook
    payload = request.body.read
    signature = request.headers['Polar-Signature']
    
    unless verify_webhook_signature(payload, signature)
      head :unauthorized
      return
    end
    
    event = JSON.parse(payload)
    
    case event['type']
    when 'order.completed'
      handle_credit_purchase(event['data'])
    when 'payment.succeeded'
      handle_payment_succeeded(event['data'])
    when 'payment.failed'
      handle_payment_failed(event['data'])
    when 'refund.created'
      handle_refund_created(event['data'])
    when 'customer.updated'
      handle_customer_updated(event['data'])
    else
      Rails.logger.info "Unhandled credit webhook event: #{event['type']}"
    end
    
    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error "Invalid JSON in credit webhook: #{e.message}"
    head :bad_request
  rescue => e
    Rails.logger.error "Credit webhook processing error: #{e.message}"
    head :internal_server_error
  end

  private

  def handle_credit_purchase(order_data)
    user = find_user_by_customer_id(order_data['customer_id'])
    return unless user

    Rails.logger.info "Processing credit purchase for user #{user.id}"
    
    # Extract credit package information
    package_id = order_data['metadata']&.dig('package_id')
    credits_amount = order_data['metadata']&.dig('credits_amount')&.to_f
    
    unless credits_amount&.positive?
      Rails.logger.warn "Invalid credits amount in order: #{order_data['id']}"
      return
    end
    
    package = CreditPackage.find_by(id: package_id) if package_id
    
    User.transaction do
      # Add credits to user account
      transaction = user.add_credits!(
        credits_amount,
        package: package,
        polar_order_id: order_data['id'],
        description: package ? "Purchased #{package.name}" : "Credit purchase"
      )
      
      # Send purchase confirmation email
      CreditMailer.purchase_confirmation(user, transaction, package).deliver_later
      
      # Check if this resolves any low balance alerts
      resolve_low_balance_alerts(user)
      
      # Track purchase event
      track_credit_event(user, 'credits_purchased', {
        amount: credits_amount,
        package_id: package_id,
        order_id: order_data['id'],
        total_cost: order_data['amount'] / 100.0
      })
      
      Rails.logger.info "Successfully added #{credits_amount} credits to user #{user.id}"
    end
  end

  def handle_payment_succeeded(payment_data)
    # Handle successful auto-recharge payments
    order_id = payment_data['order_id']
    return unless order_id
    
    # Find the order and process it
    order_data = fetch_order_from_polar(order_id)
    handle_credit_purchase(order_data) if order_data
  end

  def handle_payment_failed(payment_data)
    user = find_user_by_customer_id(payment_data['customer_id'])
    return unless user

    Rails.logger.info "Processing payment failure for user #{user.id}"
    
    # Check if this was an auto-recharge attempt
    if payment_data['metadata']&.dig('auto_recharge') == 'true'
      handle_auto_recharge_failure(user, payment_data)
    else
      handle_manual_payment_failure(user, payment_data)
    end
  end

  def handle_auto_recharge_failure(user, payment_data)
    # Disable auto-recharge temporarily and notify user
    user.update!(auto_recharge_enabled: false)
    
    # Create alert
    user.credit_alerts.create!(
      alert_type: 'auto_recharge_failed',
      current_balance: user.credit_balance,
      message: "Auto-recharge failed due to payment issues. Please update your payment method.",
      triggered_at: Time.current,
      metadata: {
        payment_id: payment_data['id'],
        failure_reason: payment_data['failure_reason']
      }
    )
    
    # Send notification email
    CreditMailer.auto_recharge_failed(user, payment_data).deliver_later
    
    track_credit_event(user, 'auto_recharge_failed', {
      payment_id: payment_data['id'],
      failure_reason: payment_data['failure_reason']
    })
  end

  def handle_manual_payment_failure(user, payment_data)
    # Send payment failure notification
    CreditMailer.payment_failed(user, payment_data).deliver_later
    
    track_credit_event(user, 'payment_failed', {
      payment_id: payment_data['id'],
      failure_reason: payment_data['failure_reason']
    })
  end

  def handle_refund_created(refund_data)
    # Find the original transaction and process refund
    polar_order_id = refund_data['order_id']
    original_transaction = CreditTransaction.find_by(polar_order_id: polar_order_id)
    
    return unless original_transaction
    
    user = original_transaction.user
    refund_amount = refund_data['amount'] / 100.0 # Convert from cents
    
    Rails.logger.info "Processing refund for user #{user.id}: #{refund_amount} credits"
    
    User.transaction do
      # Deduct credits from user account
      if user.credit_balance >= original_transaction.amount
        user.update!(credit_balance: user.credit_balance - original_transaction.amount)
        
        # Create refund transaction record
        user.credit_transactions.create!(
          transaction_type: 'refund',
          amount: -original_transaction.amount,
          balance_before: user.credit_balance + original_transaction.amount,
          balance_after: user.credit_balance,
          description: "Refund for order #{polar_order_id}",
          reference_id: original_transaction.id,
          polar_transaction_id: refund_data['id'],
          processed_at: Time.current
        )
        
        # Mark original transaction as refunded
        original_transaction.update!(status: 'refunded')
        
        # Send refund confirmation
        CreditMailer.refund_processed(user, original_transaction, refund_data).deliver_later
        
        track_credit_event(user, 'credits_refunded', {
          amount: original_transaction.amount,
          refund_id: refund_data['id'],
          original_transaction_id: original_transaction.id
        })
      else
        # Insufficient balance for full refund - handle partial refund
        handle_partial_refund(user, original_transaction, refund_data)
      end
    end
  end

  def handle_partial_refund(user, original_transaction, refund_data)
    available_balance = user.credit_balance
    
    # Deduct available balance
    user.update!(credit_balance: 0)
    
    # Create partial refund record
    user.credit_transactions.create!(
      transaction_type: 'refund',
      amount: -available_balance,
      balance_before: available_balance,
      balance_after: 0,
      description: "Partial refund for order #{original_transaction.polar_order_id} (insufficient balance)",
      reference_id: original_transaction.id,
      polar_transaction_id: refund_data['id'],
      processed_at: Time.current,
      metadata: {
        partial_refund: true,
        original_amount: original_transaction.amount,
        refunded_amount: available_balance
      }
    )
    
    # Send partial refund notification
    CreditMailer.partial_refund_processed(user, original_transaction, available_balance, refund_data).deliver_later
    
    track_credit_event(user, 'credits_partially_refunded', {
      original_amount: original_transaction.amount,
      refunded_amount: available_balance,
      refund_id: refund_data['id']
    })
  end

  def handle_customer_updated(customer_data)
    user = find_user_by_customer_id(customer_data['id'])
    return unless user

    # Update user information if needed
    user.update!(
      email: customer_data['email'] || user.email
    )
  end

  # Auto-recharge management
  def process_auto_recharge(user)
    return unless user.auto_recharge_enabled?
    return unless user.credit_balance <= user.auto_recharge_threshold
    return if recent_auto_recharge?(user)
    
    package = user.auto_recharge_package
    return unless package
    
    Rails.logger.info "Processing auto-recharge for user #{user.id}"
    
    begin
      # Create checkout for auto-recharge
      checkout = user.create_credit_purchase_checkout(package.id)
      
      # Process payment automatically if customer has saved payment method
      if checkout && process_auto_payment(checkout, user)
        # Payment will be processed via webhook
        track_credit_event(user, 'auto_recharge_initiated', {
          package_id: package.id,
          threshold_balance: user.auto_recharge_threshold,
          current_balance: user.credit_balance
        })
      end
    rescue => e
      Rails.logger.error "Auto-recharge failed for user #{user.id}: #{e.message}"
      handle_auto_recharge_failure(user, { 'failure_reason' => e.message })
    end
  end

  def process_auto_payment(checkout, user)
    # This would integrate with Polar's automatic payment processing
    # Implementation depends on Polar's specific API for saved payment methods
    false
  end

  def recent_auto_recharge?(user)
    user.last_recharge_at && user.last_recharge_at > 1.hour.ago
  end

  # Utility methods
  def find_user_by_customer_id(customer_id)
    User.find_by(polar_customer_id: customer_id)
  end

  def fetch_order_from_polar(order_id)
    begin
      Polar.client.orders.retrieve(order_id)
    rescue Polar::APIError => e
      Rails.logger.error "Failed to fetch order #{order_id}: #{e.message}"
      nil
    end
  end

  def resolve_low_balance_alerts(user)
    # Mark low balance alerts as resolved if balance is now sufficient
    if user.credit_balance > user.auto_recharge_threshold
      user.credit_alerts.where(alert_type: ['low_balance', 'zero_balance'], status: 'active')
          .update_all(status: 'dismissed', dismissed_at: Time.current)
    end
  end

  def track_credit_event(user, event_type, properties = {})
    Analytics.track(
      user_id: user.id,
      event: event_type,
      properties: properties.merge({
        timestamp: Time.current,
        user_balance: user.credit_balance
      })
    )
  rescue => e
    Rails.logger.error "Failed to track credit event: #{e.message}"
  end

  def verify_webhook_signature(payload, signature)
    # Implement signature verification according to Polar's documentation
    true
  end
end