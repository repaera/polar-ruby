# frozen_string_literal: true

class CreditPackage < ApplicationRecord
  has_many :credit_transactions, dependent: :restrict_with_error
  has_many :users_with_auto_recharge, class_name: 'User', foreign_key: 'auto_recharge_package_id'

  validates :name, presence: true
  validates :credits, presence: true, numericality: { greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :price_per_credit, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :polar_product_id, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :featured, -> { where(featured: true) }
  scope :ordered, -> { order(:sort_order, :price) }
  scope :available_for_user, ->(user) { 
    active.where(
      'expires_at IS NULL OR expires_at > ?', Time.current
    ).where(
      'max_purchases_per_user IS NULL OR max_purchases_per_user > (?)', 
      user.credit_transactions.where(credit_package: self).count
    )
  }

  before_validation :calculate_price_per_credit
  before_validation :calculate_discount_percentage

  def self.recommended_for_usage(monthly_usage)
    # Find package that provides 1.2x the monthly usage for buffer
    target_credits = monthly_usage * 1.2
    
    active.ordered.find { |package| package.credits >= target_credits } || active.ordered.last
  end

  def self.best_value
    active.ordered.min_by(&:price_per_credit)
  end

  def savings_compared_to_smallest
    smallest_package = self.class.active.ordered.first
    return 0 unless smallest_package && smallest_package != self
    
    cost_if_buying_smallest = (credits / smallest_package.credits) * smallest_package.price
    savings = cost_if_buying_smallest - price
    
    [(savings / cost_if_buying_smallest * 100).round, 0].max
  end

  def equivalent_api_calls
    (credits / CreditCostCalculator.cost_for_operation('basic_api_call')).to_i
  end

  def equivalent_image_processing
    (credits / CreditCostCalculator.cost_for_operation('image_processing')).to_i
  end

  def available_for_user?(user)
    return false unless active?
    return false if expires_at && expires_at <= Time.current
    return false if max_purchases_per_user && user.credit_transactions.where(credit_package: self).count >= max_purchases_per_user
    
    true
  end

  def purchase_count
    credit_transactions.where(transaction_type: 'purchase').count
  end

  def total_revenue
    credit_transactions.where(transaction_type: 'purchase').sum do |transaction|
      price # Use current price as approximation
    end
  end

  def is_expired?
    expires_at && expires_at <= Time.current
  end

  def days_until_expiration
    return nil unless expires_at
    return 0 if expired?
    
    ((expires_at - Time.current) / 1.day).ceil
  end

  def formatted_price
    return 'Free' if price.zero?
    
    case currency.upcase
    when 'USD'
      "$#{price.to_f}"
    when 'EUR'
      "€#{price.to_f}"
    else
      "#{price.to_f} #{currency}"
    end
  end

  def formatted_credits
    if credits >= 1_000_000
      "#{(credits / 1_000_000.0).round(1)}M"
    elsif credits >= 1_000
      "#{(credits / 1_000.0).round(1)}K"
    else
      credits.to_i.to_s
    end
  end

  def bonus_percentage
    return 0 unless discount_percentage.positive?
    
    # Calculate how much extra credits you get vs base package
    base_package = self.class.active.ordered.first
    return 0 unless base_package && base_package != self
    
    expected_credits_for_price = price / base_package.price_per_credit
    bonus_credits = credits - expected_credits_for_price
    
    return 0 if bonus_credits <= 0
    
    (bonus_credits / expected_credits_for_price * 100).round
  end

  def marketing_highlights
    highlights = []
    
    highlights << "Best Value" if self == self.class.best_value
    highlights << "Most Popular" if featured?
    highlights << "#{savings_compared_to_smallest}% Savings" if savings_compared_to_smallest > 0
    highlights << "#{bonus_percentage}% Bonus Credits" if bonus_percentage > 0
    highlights << "Limited Time" if expires_at && days_until_expiration && days_until_expiration <= 7
    
    highlights
  end

  def suitable_for_usage_pattern?(daily_usage)
    # Check if this package would last at least 30 days with current usage
    days_coverage = credits / daily_usage
    days_coverage >= 30
  end

  private

  def calculate_price_per_credit
    return if price.nil? || credits.nil? || credits.zero?
    
    self.price_per_credit = price / credits
  end

  def calculate_discount_percentage
    return unless price_per_credit
    
    # Compare to the most expensive package (smallest) to calculate discount
    base_package = self.class.active.ordered.first
    return unless base_package && base_package != self
    
    if base_package.price_per_credit > price_per_credit
      savings = base_package.price_per_credit - price_per_credit
      self.discount_percentage = (savings / base_package.price_per_credit * 100).round
    else
      self.discount_percentage = 0
    end
  end
end