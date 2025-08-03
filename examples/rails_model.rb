# frozen_string_literal: true

class User < ApplicationRecord
  has_many :subscriptions, dependent: :destroy
  has_many :orders, dependent: :destroy

  def polar_customer
    @polar_customer ||= find_or_create_polar_customer
  end

  def active_subscription?
    subscriptions.active.exists?
  end

  def subscription_benefits
    return [] unless active_subscription?
    
    active_subscription.product_benefits
  end

  def has_benefit?(benefit_type)
    subscription_benefits.any? { |benefit| benefit["type"] == benefit_type }
  end

  def create_portal_session(return_url: nil)
    customer = polar_customer
    return nil unless customer

    begin
      polar_client.customers.portal_session(
        customer["id"],
        return_url: return_url || Rails.application.routes.url_helpers.dashboard_url
      )
    rescue Polar::APIError => e
      Rails.logger.error "Failed to create portal session: #{e.message}"
      nil
    end
  end

  private

  def find_or_create_polar_customer
    begin
      result = polar_client.customers.lookup_by_email(email)
      
      if result[:data].present?
        result[:data].first
      else
        polar_client.customers.create({
          email: email,
          external_id: id.to_s,
          name: full_name,
          metadata: {
            created_via: "rails_app",
            user_id: id
          }
        })
      end
    rescue Polar::APIError => e
      Rails.logger.error "Failed to find/create Polar customer: #{e.message}"
      nil
    end
  end

  def polar_client
    @polar_client ||= Polar.client
  end
end

class Subscription < ApplicationRecord
  belongs_to :user

  scope :active, -> { where(status: ["active", "trialing"]) }
  scope :cancelled, -> { where(status: "cancelled") }

  def polar_subscription
    @polar_subscription ||= polar_client.subscriptions.retrieve(polar_subscription_id)
  rescue Polar::NotFoundError
    nil
  end

  def product_benefits
    return [] unless polar_subscription_id

    begin
      result = polar_client.subscriptions.export_benefits(polar_subscription_id)
      result["benefits"] || []
    rescue Polar::APIError
      []
    end
  end

  def cancel!(at_period_end: true)
    begin
      result = polar_client.subscriptions.cancel(polar_subscription_id, cancel_at_period_end: at_period_end)
      
      update!(
        status: result["status"],
        cancelled_at: Time.current,
        cancel_at_period_end: at_period_end
      )
      
      result
    rescue Polar::APIError => e
      errors.add(:base, "Failed to cancel subscription: #{e.message}")
      false
    end
  end

  def reactivate!
    begin
      result = polar_client.subscriptions.reactivate(polar_subscription_id)
      
      update!(
        status: result["status"],
        cancelled_at: nil,
        cancel_at_period_end: false
      )
      
      result
    rescue Polar::APIError => e
      errors.add(:base, "Failed to reactivate subscription: #{e.message}")
      false
    end
  end

  def change_product!(new_product_id, price_id: nil)
    begin
      result = polar_client.subscriptions.change_product(
        polar_subscription_id,
        new_product_id,
        price_id: price_id
      )
      
      update!(
        product_id: new_product_id,
        status: result["status"]
      )
      
      result
    rescue Polar::APIError => e
      errors.add(:base, "Failed to change subscription: #{e.message}")
      false
    end
  end

  private

  def polar_client
    @polar_client ||= Polar.client
  end
end

class Order < ApplicationRecord
  belongs_to :user

  def polar_order
    @polar_order ||= polar_client.orders.retrieve(polar_order_id)
  rescue Polar::NotFoundError
    nil
  end

  def invoice_url
    begin
      invoice = polar_client.orders.invoice(polar_order_id)
      invoice["url"]
    rescue Polar::APIError
      nil
    end
  end

  private

  def polar_client
    @polar_client ||= Polar.client
  end
end