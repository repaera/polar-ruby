# frozen_string_literal: true

class CreditsController < ApplicationController
  before_action :authenticate_user!
  before_action :find_credit_package, only: [:show_package, :purchase_package]

  def index
    @current_balance = current_user.credit_balance
    @credit_packages = CreditPackage.available_for_user(current_user).ordered
    @recent_transactions = current_user.credit_transactions.order(created_at: :desc).limit(10)
    @usage_this_month = current_user.credit_usage_this_month
    @projected_days_remaining = current_user.projected_days_remaining
    @auto_recharge_enabled = current_user.auto_recharge_enabled?
  end

  def purchase
    @credit_packages = CreditPackage.available_for_user(current_user).ordered
    @recommended_package = CreditPackage.recommended_for_usage(current_user.daily_usage_average * 30)
    @current_balance = current_user.credit_balance
  end

  def purchase_package
    begin
      checkout = current_user.create_credit_purchase_checkout(@credit_package.id)
      redirect_to checkout['url'], allow_other_host: true
    rescue => e
      Rails.logger.error "Credit purchase failed: #{e.message}"
      redirect_to purchase_credits_path, alert: 'Failed to create checkout. Please try again.'
    end
  end

  def success
    session_id = params[:session_id]
    redirect_to credits_path, alert: 'Invalid session' unless session_id

    begin
      checkout = Polar.client.checkouts.retrieve(session_id)
      
      if checkout['status'] == 'completed'
        flash[:notice] = 'Credits purchased successfully!'
        redirect_to credits_path
      else
        redirect_to purchase_credits_path, alert: 'Purchase not completed. Please try again.'
      end
    rescue Polar::NotFoundError
      redirect_to purchase_credits_path, alert: 'Invalid checkout session'
    end
  end

  def transactions
    @transactions = current_user.credit_transactions
                                .includes(:credit_package)
                                .order(created_at: :desc)
                                .page(params[:page])
                                .per(25)
    
    @filter_type = params[:type]
    @transactions = @transactions.where(transaction_type: @filter_type) if @filter_type.present?
    
    @total_purchased = current_user.total_credits_purchased
    @total_consumed = current_user.total_credits_consumed
  end

  def usage_analytics
    @time_period = params[:period] || '30_days'
    @start_date = parse_time_period(@time_period)
    
    @usage_by_operation = current_user.usage_records
                                     .joins(:credit_transaction)
                                     .where(credit_transactions: { created_at: @start_date..Time.current })
                                     .group(:operation_type)
                                     .sum(:credits_consumed)
    
    @daily_usage = current_user.usage_records
                              .joins(:credit_transaction)
                              .where(credit_transactions: { created_at: @start_date..Time.current })
                              .group_by_day(:created_at)
                              .sum(:credits_consumed)
    
    @top_operations = current_user.top_operations_by_usage(10)
    @average_daily_usage = current_user.daily_usage_average(@time_period == '30_days' ? 30 : 7)
    @projected_monthly_cost = estimate_monthly_cost
  end

  def cost_estimator
    operation_type = params[:operation_type]
    parameters = params[:parameters] || {}
    
    if operation_type.present?
      cost = CreditCostCalculator.calculate_cost(operation_type, parameters)
      breakdown = CreditCostCalculator.new(operation_type, parameters).cost_breakdown
      
      render json: {
        cost: cost,
        breakdown: breakdown,
        can_afford: current_user.sufficient_credits?(cost),
        balance_after: current_user.credit_balance - cost
      }
    else
      render json: { error: 'Operation type required' }, status: 400
    end
  end

  def auto_recharge_settings
    @auto_recharge_packages = CreditPackage.active.ordered
    @current_settings = {
      enabled: current_user.auto_recharge_enabled?,
      threshold: current_user.auto_recharge_threshold,
      package_id: current_user.auto_recharge_package_id
    }
  end

  def update_auto_recharge
    settings = auto_recharge_params
    
    if current_user.update(settings)
      flash[:notice] = 'Auto-recharge settings updated successfully'
      redirect_to auto_recharge_settings_credits_path
    else
      flash[:alert] = current_user.errors.full_messages.join(', ')
      redirect_to auto_recharge_settings_credits_path
    end
  end

  def balance_check
    render json: {
      balance: current_user.credit_balance,
      formatted_balance: "#{current_user.credit_balance} credits",
      last_updated: current_user.updated_at.iso8601
    }
  end

  def operation_pricing
    @operation_costs = CreditCostCalculator::OPERATION_COSTS
    @size_multipliers = CreditCostCalculator::SIZE_MULTIPLIERS
    @complexity_multipliers = CreditCostCalculator::COMPLEXITY_MULTIPLIERS
  end

  def consumption_forecast
    days = params[:days]&.to_i || 30
    
    avg_daily_usage = current_user.daily_usage_average
    projected_usage = avg_daily_usage * days
    
    render json: {
      daily_average: avg_daily_usage,
      projected_usage: projected_usage,
      current_balance: current_user.credit_balance,
      days_covered: current_user.projected_days_remaining,
      recommendation: projected_usage > current_user.credit_balance ? 'purchase_needed' : 'sufficient'
    }
  end

  def low_balance_simulation
    # Simulate various balance levels to help users understand when they'll need more credits
    current_usage_rate = current_user.daily_usage_average
    
    simulations = [
      { balance: 1000, days_remaining: 1000 / current_usage_rate },
      { balance: 500, days_remaining: 500 / current_usage_rate },
      { balance: 100, days_remaining: 100 / current_usage_rate },
      { balance: 50, days_remaining: 50 / current_usage_rate }
    ]
    
    render json: {
      current_balance: current_user.credit_balance,
      current_usage_rate: current_usage_rate,
      simulations: simulations,
      auto_recharge_threshold: current_user.auto_recharge_threshold
    }
  end

  private

  def find_credit_package
    @credit_package = CreditPackage.find(params[:package_id] || params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to purchase_credits_path, alert: 'Credit package not found'
  end

  def auto_recharge_params
    params.require(:user).permit(
      :auto_recharge_enabled,
      :auto_recharge_threshold,
      :auto_recharge_package_id
    )
  end

  def parse_time_period(period)
    case period
    when '7_days'
      7.days.ago
    when '30_days'
      30.days.ago
    when '90_days'
      90.days.ago
    when '1_year'
      1.year.ago
    else
      30.days.ago
    end
  end

  def estimate_monthly_cost
    daily_avg = current_user.daily_usage_average
    monthly_usage = daily_avg * 30
    
    # Find cheapest package that covers monthly usage
    suitable_package = CreditPackage.active.ordered.find { |p| p.credits >= monthly_usage }
    suitable_package&.price || 0
  end
end