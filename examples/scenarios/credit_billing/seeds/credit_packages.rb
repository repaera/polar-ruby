# frozen_string_literal: true

# Seed data for credit packages
# Run with: rails runner examples/scenarios/credit_billing/seeds/credit_packages.rb

puts "Creating credit packages..."

# Starter package
CreditPackage.find_or_create_by(name: 'Starter Credits') do |package|
  package.description = 'Perfect for trying out our services'
  package.credits = 1000
  package.price = 10.00
  package.currency = 'USD'
  package.polar_product_id = ENV['POLAR_CREDITS_STARTER_PRODUCT_ID'] || 'credits_starter_test'
  package.active = true
  package.featured = false
  package.sort_order = 1
  package.metadata = {
    'equivalent_api_calls' => 1000,
    'equivalent_image_processing' => 100,
    'recommended_for' => 'individuals'
  }
end

# Professional package (most popular)
CreditPackage.find_or_create_by(name: 'Professional Credits') do |package|
  package.description = 'Great value for regular users'
  package.credits = 5000
  package.price = 40.00
  package.currency = 'USD'
  package.polar_product_id = ENV['POLAR_CREDITS_PRO_PRODUCT_ID'] || 'credits_pro_test'
  package.active = true
  package.featured = true
  package.sort_order = 2
  package.metadata = {
    'equivalent_api_calls' => 5000,
    'equivalent_image_processing' => 500,
    'recommended_for' => 'professionals',
    'savings' => '20%'
  }
end

# Business package
CreditPackage.find_or_create_by(name: 'Business Credits') do |package|
  package.description = 'Perfect for growing businesses'
  package.credits = 15000
  package.price = 105.00
  package.currency = 'USD'
  package.polar_product_id = ENV['POLAR_CREDITS_BUSINESS_PRODUCT_ID'] || 'credits_business_test'
  package.active = true
  package.featured = false
  package.sort_order = 3
  package.metadata = {
    'equivalent_api_calls' => 15000,
    'equivalent_image_processing' => 1500,
    'recommended_for' => 'small_businesses',
    'savings' => '30%'
  }
end

# Enterprise package
CreditPackage.find_or_create_by(name: 'Enterprise Credits') do |package|
  package.description = 'Maximum value for heavy usage'
  package.credits = 50000
  package.price = 300.00
  package.currency = 'USD'
  package.polar_product_id = ENV['POLAR_CREDITS_ENTERPRISE_PRODUCT_ID'] || 'credits_enterprise_test'
  package.active = true
  package.featured = false
  package.sort_order = 4
  package.metadata = {
    'equivalent_api_calls' => 50000,
    'equivalent_image_processing' => 5000,
    'recommended_for' => 'enterprises',
    'savings' => '40%'
  }
end

# Bonus package (limited time)
CreditPackage.find_or_create_by(name: 'Holiday Bonus') do |package|
  package.description = 'Limited time bonus package with extra credits'
  package.credits = 7500
  package.price = 40.00
  package.currency = 'USD'
  package.polar_product_id = ENV['POLAR_CREDITS_BONUS_PRODUCT_ID'] || 'credits_bonus_test'
  package.active = true
  package.featured = false
  package.sort_order = 5
  package.expires_at = 30.days.from_now
  package.max_purchases_per_user = 1
  package.metadata = {
    'equivalent_api_calls' => 7500,
    'equivalent_image_processing' => 750,
    'recommended_for' => 'all_users',
    'bonus_credits' => 2500,
    'promotion' => 'holiday_2024'
  }
end

puts "Created #{CreditPackage.count} credit packages"

# Create sample users with different credit scenarios
puts "Creating sample users..."

# High balance user
high_balance_user = User.find_or_create_by(email: 'high-credits@example.com') do |user|
  user.first_name = 'High'
  user.last_name = 'Balance'
  user.credit_balance = 25000
  user.auto_recharge_enabled = false
  user.auto_recharge_threshold = 1000
  user.total_credits_purchased = 30000
  user.total_credits_consumed = 5000
  user.last_recharge_at = 1.week.ago
end

# Low balance user (needs more credits)
low_balance_user = User.find_or_create_by(email: 'low-credits@example.com') do |user|
  user.first_name = 'Low'
  user.last_name = 'Balance'
  user.credit_balance = 150
  user.auto_recharge_enabled = true
  user.auto_recharge_threshold = 500
  user.auto_recharge_amount = 5000
  user.auto_recharge_package = CreditPackage.find_by(name: 'Professional Credits')
  user.total_credits_purchased = 10000
  user.total_credits_consumed = 9850
  user.last_recharge_at = 2.weeks.ago
end

# New user with welcome credits
new_user = User.find_or_create_by(email: 'new-credits@example.com') do |user|
  user.first_name = 'New'
  user.last_name = 'User'
  user.credit_balance = 100 # Welcome credits
  user.auto_recharge_enabled = false
  user.auto_recharge_threshold = 100
  user.total_credits_purchased = 100
  user.total_credits_consumed = 0
end

# Create sample transactions for demo
puts "Creating sample credit transactions..."

# High balance user transactions
if high_balance_user.credit_transactions.empty?
  # Purchase transactions
  high_balance_user.credit_transactions.create!(
    transaction_type: 'purchase',
    amount: 15000,
    balance_before: 0,
    balance_after: 15000,
    description: 'Purchased Business Credits package',
    credit_package: CreditPackage.find_by(name: 'Business Credits'),
    polar_order_id: "order_#{SecureRandom.hex(8)}",
    processed_at: 2.weeks.ago
  )
  
  high_balance_user.credit_transactions.create!(
    transaction_type: 'purchase',
    amount: 15000,
    balance_before: 10000,
    balance_after: 25000,
    description: 'Purchased Business Credits package',
    credit_package: CreditPackage.find_by(name: 'Business Credits'),
    polar_order_id: "order_#{SecureRandom.hex(8)}",
    processed_at: 1.week.ago
  )
  
  # Consumption transactions
  (1..10).each do |i|
    high_balance_user.credit_transactions.create!(
      transaction_type: 'consumption',
      amount: -500,
      balance_before: 25000 + (500 * i),
      balance_after: 25000 + (500 * (i - 1)),
      description: 'API calls and image processing',
      operation_type: 'api_call',
      processed_at: i.days.ago
    )
  end
end

# Low balance user transactions
if low_balance_user.credit_transactions.empty?
  # Purchase transactions
  low_balance_user.credit_transactions.create!(
    transaction_type: 'purchase',
    amount: 5000,
    balance_before: 0,
    balance_after: 5000,
    description: 'Purchased Professional Credits package',
    credit_package: CreditPackage.find_by(name: 'Professional Credits'),
    polar_order_id: "order_#{SecureRandom.hex(8)}",
    processed_at: 3.weeks.ago
  )
  
  low_balance_user.credit_transactions.create!(
    transaction_type: 'purchase',
    amount: 5000,
    balance_before: 1000,
    balance_after: 6000,
    description: 'Auto-recharge: Professional Credits',
    credit_package: CreditPackage.find_by(name: 'Professional Credits'),
    polar_order_id: "order_#{SecureRandom.hex(8)}",
    processed_at: 2.weeks.ago
  )
  
  # Heavy consumption
  (1..25).each do |i|
    low_balance_user.credit_transactions.create!(
      transaction_type: 'consumption',
      amount: -200,
      balance_before: 6000 - (200 * (i - 1)),
      balance_after: 6000 - (200 * i),
      description: 'Image processing and AI analysis',
      operation_type: ['image_processing', 'ai_analysis', 'api_call'].sample,
      processed_at: i.days.ago
    )
  end
end

# New user welcome credits
if new_user.credit_transactions.empty?
  new_user.credit_transactions.create!(
    transaction_type: 'bonus',
    amount: 100,
    balance_before: 0,
    balance_after: 100,
    description: 'Welcome bonus credits',
    processed_at: 1.day.ago
  )
end

# Create sample usage records
puts "Creating sample usage records..."

high_balance_user.credit_transactions.where(transaction_type: 'consumption').each do |transaction|
  UsageRecord.create!(
    user: high_balance_user,
    credit_transaction: transaction,
    operation_type: transaction.operation_type,
    operation_id: "op_#{SecureRandom.hex(6)}",
    credits_consumed: transaction.amount.abs,
    cost_per_unit: 5.0,
    units_consumed: (transaction.amount.abs / 5).to_i,
    operation_details: {
      'complexity' => 'standard',
      'file_size' => '2MB',
      'processing_time' => '1.2s'
    },
    api_endpoint: '/api/v1/process',
    status: 'success',
    started_at: transaction.created_at,
    completed_at: transaction.created_at + 2.seconds
  )
end

# Create credit alerts for low balance user
puts "Creating sample credit alerts..."

if low_balance_user.credit_alerts.empty?
  low_balance_user.credit_alerts.create!(
    alert_type: 'low_balance',
    trigger_balance: 500,
    current_balance: 150,
    message: 'Your credit balance is running low. Current balance: 150 credits.',
    triggered_at: 1.day.ago,
    email_sent: true,
    email_sent_at: 1.day.ago
  )
end

puts "Created sample users:"
puts "- High balance user: #{high_balance_user.email} (#{high_balance_user.credit_balance} credits)"
puts "- Low balance user: #{low_balance_user.email} (#{low_balance_user.credit_balance} credits, auto-recharge enabled)"
puts "- New user: #{new_user.email} (#{new_user.credit_balance} welcome credits)"

puts "\nCreated #{CreditTransaction.count} credit transactions"
puts "Created #{UsageRecord.count} usage records"
puts "Created #{CreditAlert.count} credit alerts"

puts "\nCredit billing seed data complete!"
puts "You can now test the credit billing scenario with these sample users."