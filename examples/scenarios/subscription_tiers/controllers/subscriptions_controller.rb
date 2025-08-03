# frozen_string_literal: true

class SubscriptionsController < ApplicationController
  before_action :authenticate_user!
  before_action :find_subscription, only: [:show, :cancel, :reactivate, :change_tier]

  def index
    @active_subscription = current_user.active_subscription
    @subscription_history = current_user.subscriptions.order(created_at: :desc)
    @usage_quota = current_user.usage_quota
    @tier_definitions = TierDefinition.active.ordered
  end

  def show
    @usage_quota = current_user.usage_quota
    @tier_definition = TierDefinition.find_by(name: @subscription.tier)
  end

  def new
    @tier = params[:tier] || 'starter'
    @billing_interval = params[:billing_interval] || 'monthly'
    @tier_definition = TierDefinition.find_by(name: @tier)
    
    redirect_to pricing_path, alert: 'Invalid tier selected' unless @tier_definition
  end

  def create
    @tier = params[:tier]
    @billing_interval = params[:billing_interval] || 'monthly'
    
    begin
      checkout = current_user.create_checkout_session(@tier, @billing_interval)
      redirect_to checkout['url'], allow_other_host: true
    rescue => e
      Rails.logger.error "Subscription creation failed: #{e.message}"
      redirect_to pricing_path, alert: 'Failed to create subscription. Please try again.'
    end
  end

  def success
    session_id = params[:session_id]
    redirect_to subscriptions_path, alert: 'Invalid session' unless session_id

    begin
      checkout = Polar.client.checkouts.retrieve(session_id)
      
      if checkout['status'] == 'completed'
        flash[:notice] = 'Subscription created successfully! Welcome aboard!'
        redirect_to subscriptions_path
      else
        redirect_to pricing_path, alert: 'Subscription not completed. Please try again.'
      end
    rescue Polar::NotFoundError
      redirect_to pricing_path, alert: 'Invalid checkout session'
    end
  end

  def cancel
    if @subscription.cancel!(at_period_end: params[:immediate] != 'true')
      if @subscription.cancel_at_period_end?
        flash[:notice] = "Subscription will be cancelled at the end of your billing period (#{@subscription.current_period_end.strftime('%B %d, %Y')})"
      else
        flash[:notice] = 'Subscription cancelled immediately'
      end
    else
      flash[:alert] = @subscription.errors.full_messages.join(', ')
    end
    
    redirect_to subscription_path(@subscription)
  end

  def reactivate
    if @subscription.reactivate!
      flash[:notice] = 'Subscription reactivated successfully!'
    else
      flash[:alert] = @subscription.errors.full_messages.join(', ')
    end
    
    redirect_to subscription_path(@subscription)
  end

  def change_tier
    new_tier = params[:new_tier]
    billing_interval = params[:billing_interval] || @subscription.billing_interval
    
    tier_definition = TierDefinition.find_by(name: new_tier)
    redirect_to subscription_path(@subscription), alert: 'Invalid tier selected' unless tier_definition

    # Check if this is an upgrade or downgrade
    is_upgrade = tier_definition.is_upgrade_from?(@subscription.tier)
    
    if is_upgrade
      # For upgrades, charge prorated amount immediately
      handle_upgrade(new_tier, billing_interval)
    else
      # For downgrades, apply at next billing cycle
      handle_downgrade(new_tier, billing_interval)
    end
  end

  def portal
    portal_url = current_user.customer_portal_url
    
    if portal_url
      redirect_to portal_url, allow_other_host: true
    else
      redirect_to subscriptions_path, alert: 'Unable to access customer portal. Please try again.'
    end
  end

  def upgrade_preview
    current_tier = params[:current_tier]
    new_tier = params[:new_tier]
    billing_interval = params[:billing_interval] || 'monthly'
    
    current_subscription = current_user.active_subscription
    
    if current_subscription
      prorate_cost = current_subscription.prorate_upgrade_cost(new_tier)
      
      render json: {
        prorate_cost: prorate_cost,
        formatted_cost: "$#{prorate_cost.round(2)}",
        next_billing_date: current_subscription.current_period_end,
        new_monthly_cost: TierDefinition.find_by(name: new_tier)&.monthly_price
      }
    else
      tier_def = TierDefinition.find_by(name: new_tier)
      cost = billing_interval == 'yearly' ? tier_def.yearly_price : tier_def.monthly_price
      
      render json: {
        prorate_cost: 0,
        formatted_cost: "$0",
        full_cost: cost,
        formatted_full_cost: "$#{cost}",
        trial_available: current_user.trial_active?
      }
    end
  end

  private

  def find_subscription
    @subscription = current_user.subscriptions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to subscriptions_path, alert: 'Subscription not found'
  end

  def handle_upgrade(new_tier, billing_interval)
    if @subscription.change_tier!(new_tier, billing_interval)
      flash[:notice] = "Successfully upgraded to #{TierDefinition.find_by(name: new_tier).display_name}!"
      
      # Track upgrade event
      track_subscription_event('tier_upgraded', {
        from_tier: @subscription.tier_was,
        to_tier: new_tier,
        billing_interval: billing_interval
      })
    else
      flash[:alert] = @subscription.errors.full_messages.join(', ')
    end
    
    redirect_to subscription_path(@subscription)
  end

  def handle_downgrade(new_tier, billing_interval)
    # For downgrades, we typically schedule the change for the next billing cycle
    # This requires additional logic to store pending changes
    
    flash[:notice] = "Your plan will be changed to #{TierDefinition.find_by(name: new_tier).display_name} at your next billing cycle."
    
    # Store pending change (you'd need to add a pending_tier field to subscriptions)
    @subscription.update!(
      pending_tier: new_tier,
      pending_billing_interval: billing_interval
    )
    
    # Track downgrade event
    track_subscription_event('tier_downgrade_scheduled', {
      from_tier: @subscription.tier,
      to_tier: new_tier,
      effective_date: @subscription.current_period_end
    })
    
    redirect_to subscription_path(@subscription)
  end

  def track_subscription_event(event_name, properties = {})
    # Integrate with your analytics service
    Analytics.track(
      user_id: current_user.id,
      event: event_name,
      properties: properties.merge({
        subscription_id: @subscription.id,
        timestamp: Time.current
      })
    )
  rescue => e
    Rails.logger.error "Failed to track event #{event_name}: #{e.message}"
  end
end