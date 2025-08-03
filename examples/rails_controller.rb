# frozen_string_literal: true

class PaymentsController < ApplicationController
  before_action :authenticate_user!

  def new
    @checkout = create_checkout_session
    redirect_to @checkout["url"], allow_other_host: true
  end

  def success
    session_id = params[:session_id]
    return redirect_to root_path, alert: "Invalid session" unless session_id

    begin
      checkout = polar_client.checkouts.retrieve(session_id)
      
      if checkout["status"] == "completed"
        process_successful_payment(checkout)
        redirect_to dashboard_path, notice: "Payment successful!"
      else
        redirect_to pricing_path, alert: "Payment not completed"
      end
    rescue Polar::NotFoundError
      redirect_to pricing_path, alert: "Invalid checkout session"
    end
  end

  def cancel
    redirect_to pricing_path, notice: "Payment cancelled"
  end

  def webhook
    payload = request.body.read
    signature = request.headers["Polar-Signature"]
    
    begin
      event = verify_webhook_signature(payload, signature)
      handle_webhook_event(event)
      
      head :ok
    rescue StandardError => e
      Rails.logger.error "Webhook error: #{e.message}"
      head :bad_request
    end
  end

  private

  def polar_client
    @polar_client ||= begin
      Polar.configure do |config|
        config.access_token = Rails.application.credentials.polar[:access_token]
        config.environment = Rails.env.production? ? :production : :sandbox
      end
      Polar.client
    end
  end

  def create_checkout_session
    product_id = params[:product_id] || "your_product_id"
    
    polar_client.checkouts.create({
      product_id: product_id,
      customer: {
        email: current_user.email,
        external_id: current_user.id.to_s
      },
      success_url: payments_success_url + "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: payments_cancel_url,
      metadata: {
        user_id: current_user.id,
        plan: params[:plan]
      }
    })
  end

  def process_successful_payment(checkout)
    subscription_data = checkout["subscription"]
    
    current_user.subscriptions.create!(
      polar_subscription_id: subscription_data["id"],
      product_id: checkout["product_id"],
      status: subscription_data["status"],
      current_period_start: Time.parse(subscription_data["current_period_start"]),
      current_period_end: Time.parse(subscription_data["current_period_end"])
    )

    grant_user_benefits(checkout["product_id"])
  end

  def grant_user_benefits(product_id)
    benefits = polar_client.products.benefits(product_id)
    
    benefits[:data].each do |benefit|
      case benefit["type"]
      when "github_repository"
        invite_to_github_repo(benefit, current_user)
      when "discord"
        invite_to_discord(benefit, current_user)
      when "custom"
        grant_custom_benefit(benefit, current_user)
      end
    end
  end

  def handle_webhook_event(event)
    case event["type"]
    when "subscription.created"
      handle_subscription_created(event["data"])
    when "subscription.cancelled" 
      handle_subscription_cancelled(event["data"])
    when "subscription.updated"
      handle_subscription_updated(event["data"])
    when "order.completed"
      handle_order_completed(event["data"])
    end
  end

  def handle_subscription_created(subscription)
    user = User.find_by(email: subscription["customer"]["email"])
    return unless user

    user.subscriptions.create!(
      polar_subscription_id: subscription["id"],
      product_id: subscription["product_id"],
      status: subscription["status"],
      current_period_start: Time.parse(subscription["current_period_start"]),
      current_period_end: Time.parse(subscription["current_period_end"])
    )
  end

  def handle_subscription_cancelled(subscription)
    user_subscription = Subscription.find_by(polar_subscription_id: subscription["id"])
    return unless user_subscription

    user_subscription.update!(
      status: "cancelled",
      cancelled_at: Time.current
    )

    revoke_user_benefits(user_subscription.user, user_subscription.product_id)
  end

  def verify_webhook_signature(payload, signature)
    JSON.parse(payload)
  end
end