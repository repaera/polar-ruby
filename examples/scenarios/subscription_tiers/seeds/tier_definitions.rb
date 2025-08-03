# frozen_string_literal: true

# Seed data for subscription tier definitions
# Run with: rails runner examples/scenarios/subscription_tiers/seeds/tier_definitions.rb

puts "Creating tier definitions..."

# Free tier (for trial ended users)
TierDefinition.find_or_create_by(name: 'free') do |tier|
  tier.display_name = 'Free'
  tier.description = 'Basic access with limited features'
  tier.monthly_price = 0
  tier.yearly_price = 0
  tier.projects_limit = 1
  tier.team_members_limit = 1
  tier.storage_limit_bytes = 100.megabytes
  tier.api_calls_limit = 100
  tier.features = {
    'advanced_analytics' => false,
    'priority_support' => false,
    'custom_integrations' => false,
    'team_collaboration' => false,
    'export_data' => false,
    'white_labeling' => false
  }
  tier.active = true
  tier.sort_order = 0
end

# Starter tier
TierDefinition.find_or_create_by(name: 'starter') do |tier|
  tier.display_name = 'Starter'
  tier.description = 'Perfect for individuals and small projects'
  tier.monthly_price = 9
  tier.yearly_price = 90 # 2 months free
  tier.polar_monthly_product_id = ENV['POLAR_STARTER_MONTHLY_PRODUCT_ID'] || 'starter_monthly_test'
  tier.polar_yearly_product_id = ENV['POLAR_STARTER_YEARLY_PRODUCT_ID'] || 'starter_yearly_test'
  tier.projects_limit = 3
  tier.team_members_limit = 1
  tier.storage_limit_bytes = 1.gigabyte
  tier.api_calls_limit = 1000
  tier.features = {
    'advanced_analytics' => false,
    'priority_support' => false,
    'custom_integrations' => false,
    'team_collaboration' => false,
    'export_data' => true,
    'white_labeling' => false
  }
  tier.active = true
  tier.sort_order = 1
end

# Pro tier (default trial tier)
TierDefinition.find_or_create_by(name: 'pro') do |tier|
  tier.display_name = 'Pro'
  tier.description = 'Great for growing teams and businesses'
  tier.monthly_price = 29
  tier.yearly_price = 290 # 2 months free
  tier.polar_monthly_product_id = ENV['POLAR_PRO_MONTHLY_PRODUCT_ID'] || 'pro_monthly_test'
  tier.polar_yearly_product_id = ENV['POLAR_PRO_YEARLY_PRODUCT_ID'] || 'pro_yearly_test'
  tier.projects_limit = 25
  tier.team_members_limit = 10
  tier.storage_limit_bytes = 10.gigabytes
  tier.api_calls_limit = 10000
  tier.features = {
    'advanced_analytics' => true,
    'priority_support' => false,
    'custom_integrations' => true,
    'team_collaboration' => true,
    'export_data' => true,
    'white_labeling' => false
  }
  tier.active = true
  tier.featured = true
  tier.sort_order = 2
end

# Enterprise tier
TierDefinition.find_or_create_by(name: 'enterprise') do |tier|
  tier.display_name = 'Enterprise'
  tier.description = 'For large organizations with advanced needs'
  tier.monthly_price = 99
  tier.yearly_price = 990 # 2 months free
  tier.polar_monthly_product_id = ENV['POLAR_ENTERPRISE_MONTHLY_PRODUCT_ID'] || 'enterprise_monthly_test'
  tier.polar_yearly_product_id = ENV['POLAR_ENTERPRISE_YEARLY_PRODUCT_ID'] || 'enterprise_yearly_test'
  tier.projects_limit = nil # Unlimited
  tier.team_members_limit = nil # Unlimited
  tier.storage_limit_bytes = 100.gigabytes
  tier.api_calls_limit = 100000
  tier.features = {
    'advanced_analytics' => true,
    'priority_support' => true,
    'custom_integrations' => true,
    'team_collaboration' => true,
    'export_data' => true,
    'white_labeling' => true,
    'sso_integration' => true,
    'audit_logs' => true,
    'dedicated_support' => true
  }
  tier.active = true
  tier.sort_order = 3
end

puts "Created #{TierDefinition.count} tier definitions"

# Create sample users with different states
puts "Creating sample users..."

# Trial user
trial_user = User.find_or_create_by(email: 'trial@example.com') do |user|
  user.first_name = 'Trial'
  user.last_name = 'User'
  user.current_tier = 'pro'
  user.trial_started_at = 15.days.ago
  user.trial_ends_at = 15.days.from_now
  user.onboarding_completed = true
end

if trial_user.usage_quota.blank?
  trial_user.create_usage_quota(
    tier: 'pro',
    **TierDefinition.quota_limits_for('pro')
  )
end

# Paid starter user
starter_user = User.find_or_create_by(email: 'starter@example.com') do |user|
  user.first_name = 'Starter'
  user.last_name = 'User'
  user.current_tier = 'starter'
  user.trial_started_at = 45.days.ago
  user.trial_ends_at = 15.days.ago
  user.onboarding_completed = true
end

if starter_user.usage_quota.blank?
  starter_user.create_usage_quota(
    tier: 'starter',
    **TierDefinition.quota_limits_for('starter')
  )
end

# Create a subscription for starter user
if starter_user.subscriptions.empty?
  starter_user.subscriptions.create!(
    polar_subscription_id: "sub_starter_#{SecureRandom.hex(8)}",
    polar_product_id: TierDefinition.find_by(name: 'starter').polar_monthly_product_id,
    tier: 'starter',
    status: 'active',
    amount: 9.00,
    currency: 'USD',
    billing_interval: 'monthly',
    current_period_start: Time.current.beginning_of_month,
    current_period_end: Time.current.end_of_month
  )
end

# Pro user
pro_user = User.find_or_create_by(email: 'pro@example.com') do |user|
  user.first_name = 'Pro'
  user.last_name = 'User'
  user.current_tier = 'pro'
  user.trial_started_at = 60.days.ago
  user.trial_ends_at = 30.days.ago
  user.onboarding_completed = true
end

if pro_user.usage_quota.blank?
  pro_user.create_usage_quota(
    tier: 'pro',
    **TierDefinition.quota_limits_for('pro')
  )
end

# Create subscription for pro user
if pro_user.subscriptions.empty?
  pro_user.subscriptions.create!(
    polar_subscription_id: "sub_pro_#{SecureRandom.hex(8)}",
    polar_product_id: TierDefinition.find_by(name: 'pro').polar_yearly_product_id,
    tier: 'pro',
    status: 'active',
    amount: 290.00,
    currency: 'USD',
    billing_interval: 'yearly',
    current_period_start: 30.days.ago,
    current_period_end: 335.days.from_now
  )
end

# Simulate some usage for demo
trial_user.usage_quota.update!(
  projects_used: 2,
  team_members_used: 1,
  storage_used_bytes: 500.megabytes,
  api_calls_used: 750
)

starter_user.usage_quota.update!(
  projects_used: 3,
  team_members_used: 1,
  storage_used_bytes: 800.megabytes,
  api_calls_used: 850
)

pro_user.usage_quota.update!(
  projects_used: 15,
  team_members_used: 8,
  storage_used_bytes: 6.gigabytes,
  api_calls_used: 7500
)

puts "Created sample users:"
puts "- Trial user: #{trial_user.email} (#{trial_user.trial_days_remaining} days remaining)"
puts "- Starter user: #{starter_user.email} (active subscription)"
puts "- Pro user: #{pro_user.email} (active yearly subscription)"

puts "\nSubscription tiers seed data complete!"
puts "You can now test the subscription tiers scenario with these sample users."