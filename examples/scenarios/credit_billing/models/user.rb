# frozen_string_literal: true

class User < ApplicationRecord
  has_many :credit_transactions, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :credit_alerts, dependent: :destroy
  belongs_to :auto_recharge_package, class_name: 'CreditPackage', optional: true

  validates :credit_balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :auto_recharge_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :auto_recharge_amount, numericality: { greater_than: 0 }

  scope :low_balance, ->(threshold = 100) { where('credit_balance < ?', threshold) }
  scope :auto_recharge_enabled, -> { where(auto_recharge_enabled: true) }
  scope :eligible_for_recharge, -> { auto_recharge_enabled.where('credit_balance <= auto_recharge_threshold') }

  after_create :grant_welcome_credits

  def sufficient_credits?(amount)
    credit_balance >= amount
  end

  def consume_credits!(amount, operation_type:, operation_id: nil, metadata: {})
    raise InsufficientCreditsError.new(amount, credit_balance) unless sufficient_credits?(amount)

    User.transaction do
      previous_balance = credit_balance
      new_balance = previous_balance - amount

      # Update user balance
      update!(
        credit_balance: new_balance,
        total_credits_consumed: total_credits_consumed + amount
      )

      # Create transaction record
      transaction = credit_transactions.create!(
        transaction_type: 'consumption',
        amount: -amount,
        balance_before: previous_balance,
        balance_after: new_balance,
        operation_type: operation_type,
        operation_id: operation_id,
        description: "Consumed #{amount} credits for #{operation_type}",
        metadata: metadata,
        processed_at: Time.current
      )

      # Create usage record
      usage_records.create!(
        credit_transaction: transaction,
        operation_type: operation_type,
        operation_id: operation_id,
        credits_consumed: amount,
        operation_details: metadata,
        started_at: Time.current,
        completed_at: Time.current,
        status: 'success'
      )

      # Check for low balance alerts
      check_for_low_balance_alerts
      
      # Trigger auto-recharge if enabled and below threshold
      trigger_auto_recharge_if_needed

      transaction
    end
  end

  def add_credits!(amount, package: nil, polar_order_id: nil, description: nil)
    User.transaction do
      previous_balance = credit_balance
      new_balance = previous_balance + amount

      # Update user balance
      update!(
        credit_balance: new_balance,
        total_credits_purchased: total_credits_purchased + amount,
        last_recharge_at: Time.current
      )

      # Create transaction record
      credit_transactions.create!(
        transaction_type: 'purchase',
        amount: amount,
        balance_before: previous_balance,
        balance_after: new_balance,
        credit_package: package,
        polar_order_id: polar_order_id,
        description: description || "Purchased #{amount} credits",
        processed_at: Time.current
      )
    end
  end

  def refund_credits!(amount, reason:, original_transaction_id: nil)
    User.transaction do
      previous_balance = credit_balance
      new_balance = previous_balance + amount

      # Update user balance
      update!(credit_balance: new_balance)

      # Create refund transaction
      credit_transactions.create!(
        transaction_type: 'refund',
        amount: amount,
        balance_before: previous_balance,
        balance_after: new_balance,
        description: "Refund: #{reason}",
        reference_id: original_transaction_id,
        processed_at: Time.current
      )
    end
  end

  def credit_usage_this_month
    start_date = Time.current.beginning_of_month
    end_date = Time.current.end_of_month
    
    credit_transactions
      .where(transaction_type: 'consumption', created_at: start_date..end_date)
      .sum('ABS(amount)')
  end

  def credit_purchases_this_month
    start_date = Time.current.beginning_of_month
    end_date = Time.current.end_of_month
    
    credit_transactions
      .where(transaction_type: 'purchase', created_at: start_date..end_date)
      .sum(:amount)
  end

  def daily_usage_average(days = 30)
    start_date = days.days.ago
    
    total_usage = credit_transactions
      .where(transaction_type: 'consumption', created_at: start_date..Time.current)
      .sum('ABS(amount)')
    
    total_usage / days
  end

  def projected_days_remaining
    return Float::INFINITY if credit_balance.zero?
    
    avg_daily_usage = daily_usage_average
    return Float::INFINITY if avg_daily_usage.zero?
    
    (credit_balance / avg_daily_usage).round(1)
  end

  def top_operations_by_usage(limit = 5)
    usage_records
      .joins(:credit_transaction)
      .where(credit_transactions: { created_at: 30.days.ago..Time.current })
      .group(:operation_type)
      .sum(:credits_consumed)
      .sort_by { |_, credits| -credits }
      .first(limit)
      .to_h
  end

  def create_credit_purchase_checkout(package_id)
    package = CreditPackage.find(package_id)
    
    Polar.client.checkouts.create({
      product_id: package.polar_product_id,
      customer: {
        email: email,
        external_id: id.to_s
      },
      success_url: Rails.application.routes.url_helpers.credits_success_url(host: Rails.application.config.app_host),
      cancel_url: Rails.application.routes.url_helpers.credits_url(host: Rails.application.config.app_host),
      metadata: {
        user_id: id,
        package_id: package_id,
        credits_amount: package.credits
      }
    })
  end

  def can_afford_operation?(operation_type)
    cost = CreditCostCalculator.cost_for_operation(operation_type)
    sufficient_credits?(cost)
  end

  def estimate_operation_cost(operation_type, parameters = {})
    CreditCostCalculator.calculate_cost(operation_type, parameters)
  end

  private

  def grant_welcome_credits
    add_credits!(100, description: 'Welcome bonus credits')
  end

  def check_for_low_balance_alerts
    return unless credit_alerts_enabled?
    
    # Check for low balance alert (below threshold)
    if credit_balance <= auto_recharge_threshold && !recent_low_balance_alert?
      credit_alerts.create!(
        alert_type: 'low_balance',
        trigger_balance: auto_recharge_threshold,
        current_balance: credit_balance,
        message: "Your credit balance is running low. Current balance: #{credit_balance} credits.",
        triggered_at: Time.current
      )
    end
    
    # Check for zero balance alert
    if credit_balance <= 0 && !recent_zero_balance_alert?
      credit_alerts.create!(
        alert_type: 'zero_balance',
        trigger_balance: 0,
        current_balance: credit_balance,
        message: "You have run out of credits. Purchase more to continue using our services.",
        triggered_at: Time.current
      )
    end
  end

  def trigger_auto_recharge_if_needed
    return unless auto_recharge_enabled?
    return unless credit_balance <= auto_recharge_threshold
    return if recent_auto_recharge?
    
    AutoRechargeJob.perform_later(id)
  end

  def recent_low_balance_alert?
    credit_alerts
      .where(alert_type: 'low_balance', triggered_at: 24.hours.ago..Time.current)
      .exists?
  end

  def recent_zero_balance_alert?
    credit_alerts
      .where(alert_type: 'zero_balance', triggered_at: 24.hours.ago..Time.current)
      .exists?
  end

  def recent_auto_recharge?
    last_recharge_at && last_recharge_at > 1.hour.ago
  end
end

class InsufficientCreditsError < StandardError
  attr_reader :required_amount, :available_amount

  def initialize(required_amount, available_amount)
    @required_amount = required_amount
    @available_amount = available_amount
    super("Insufficient credits. Required: #{required_amount}, Available: #{available_amount}")
  end
end