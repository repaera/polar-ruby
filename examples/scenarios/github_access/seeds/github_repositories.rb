# frozen_string_literal: true

# Seed data for GitHub repositories and access control
# Run with: rails runner examples/scenarios/github_access/seeds/github_repositories.rb

puts "Creating GitHub repository packages..."

# Premium Tools Package - Collection of development tools
tools_package = RepositoryPackage.find_or_create_by(name: 'Premium Dev Tools') do |package|
  package.description = 'Essential development tools and utilities for modern developers'
  package.price = 29.99
  package.currency = 'USD'
  package.polar_product_id = ENV['POLAR_TOOLS_PACKAGE_PRODUCT_ID'] || 'github_tools_package_test'
  package.access_duration = 'permanent'
  package.active = true
  package.featured = true
  package.sort_order = 1
  package.metadata = {
    'target_audience' => 'developers',
    'complexity_level' => 'intermediate',
    'maintenance_level' => 'active'
  }
end

# Enterprise Package - Advanced tools and frameworks
enterprise_package = RepositoryPackage.find_or_create_by(name: 'Enterprise Framework Suite') do |package|
  package.description = 'Advanced frameworks and enterprise-grade solutions'
  package.price = 99.99
  package.currency = 'USD'
  package.polar_product_id = ENV['POLAR_ENTERPRISE_PACKAGE_PRODUCT_ID'] || 'github_enterprise_package_test'
  package.access_duration = '1_year'
  package.active = true
  package.featured = false
  package.sort_order = 2
  package.metadata = {
    'target_audience' => 'enterprises',
    'complexity_level' => 'advanced',
    'maintenance_level' => 'active',
    'support_included' => true
  }
end

# Starter Package - Basic tools for beginners
starter_package = RepositoryPackage.find_or_create_by(name: 'Starter Kit') do |package|
  package.description = 'Perfect for beginners getting started with development'
  package.price = 9.99
  package.currency = 'USD'
  package.polar_product_id = ENV['POLAR_STARTER_PACKAGE_PRODUCT_ID'] || 'github_starter_package_test'
  package.access_duration = 'permanent'
  package.active = true
  package.featured = false
  package.sort_order = 3
  package.metadata = {
    'target_audience' => 'beginners',
    'complexity_level' => 'basic',
    'maintenance_level' => 'active'
  }
end

puts "Created #{RepositoryPackage.count} repository packages"

# Create GitHub repositories
puts "Creating GitHub repositories..."

# Premium Dev Tools Repositories
cli_tool_repo = GithubRepository.find_or_create_by(github_id: '12345001') do |repo|
  repo.name = 'premium-cli-tool'
  repo.full_name = 'devtools/premium-cli-tool'
  repo.owner = 'devtools'
  repo.description = 'Advanced CLI tool with premium features for developers'
  repo.html_url = 'https://github.com/devtools/premium-cli-tool'
  repo.clone_url = 'https://github.com/devtools/premium-cli-tool.git'
  repo.ssh_url = 'git@github.com:devtools/premium-cli-tool.git'
  repo.private = true
  repo.language = 'TypeScript'
  repo.stars_count = 1250
  repo.forks_count = 89
  repo.price = 15.00
  repo.currency = 'USD'
  repo.polar_product_id = ENV['POLAR_CLI_TOOL_PRODUCT_ID'] || 'cli_tool_individual_test'
  repo.access_expires_at = nil # Permanent access for individual purchase
  repo.active = true
  repo.metadata = {
    'installation_guide' => 'npm install -g @devtools/premium-cli',
    'documentation_url' => 'https://docs.devtools.com/cli',
    'license' => 'Commercial'
  }
end

debug_suite_repo = GithubRepository.find_or_create_by(github_id: '12345002') do |repo|
  repo.name = 'debug-suite-pro'
  repo.full_name = 'devtools/debug-suite-pro'
  repo.owner = 'devtools'
  repo.description = 'Professional debugging suite with advanced analysis tools'
  repo.html_url = 'https://github.com/devtools/debug-suite-pro'
  repo.clone_url = 'https://github.com/devtools/debug-suite-pro.git'
  repo.ssh_url = 'git@github.com:devtools/debug-suite-pro.git'
  repo.private = true
  repo.language = 'Python'
  repo.stars_count = 890
  repo.forks_count = 45
  repo.price = 25.00
  repo.currency = 'USD'
  repo.polar_product_id = ENV['POLAR_DEBUG_SUITE_PRODUCT_ID'] || 'debug_suite_individual_test'
  repo.access_expires_at = nil
  repo.active = true
  repo.metadata = {
    'installation_guide' => 'pip install debug-suite-pro',
    'python_version' => '>=3.8',
    'license' => 'Commercial'
  }
end

# Enterprise Framework Repositories
microservices_repo = GithubRepository.find_or_create_by(github_id: '12345003') do |repo|
  repo.name = 'enterprise-microservices'
  repo.full_name = 'enterprise/microservices-framework'
  repo.owner = 'enterprise'
  repo.description = 'Enterprise-grade microservices framework with advanced features'
  repo.html_url = 'https://github.com/enterprise/microservices-framework'
  repo.clone_url = 'https://github.com/enterprise/microservices-framework.git'
  repo.ssh_url = 'git@github.com:enterprise/microservices-framework.git'
  repo.private = true
  repo.language = 'Java'
  repo.stars_count = 2150
  repo.forks_count = 320
  repo.price = 199.00
  repo.currency = 'USD'
  repo.polar_product_id = ENV['POLAR_MICROSERVICES_PRODUCT_ID'] || 'microservices_individual_test'
  repo.access_expires_at = 1.year.from_now
  repo.active = true
  repo.metadata = {
    'java_version' => '>=11',
    'spring_boot' => '>=2.7',
    'license' => 'Enterprise Commercial',
    'support_included' => true
  }
end

monitoring_repo = GithubRepository.find_or_create_by(github_id: '12345004') do |repo|
  repo.name = 'enterprise-monitoring'
  repo.full_name = 'enterprise/monitoring-stack'
  repo.owner = 'enterprise'
  repo.description = 'Complete monitoring and observability stack for enterprises'
  repo.html_url = 'https://github.com/enterprise/monitoring-stack'
  repo.clone_url = 'https://github.com/enterprise/monitoring-stack.git'
  repo.ssh_url = 'git@github.com:enterprise/monitoring-stack.git'
  repo.private = true
  repo.language = 'Go'
  repo.stars_count = 1680
  repo.forks_count = 145
  repo.price = 149.00
  repo.currency = 'USD'
  repo.polar_product_id = ENV['POLAR_MONITORING_PRODUCT_ID'] || 'monitoring_individual_test'
  repo.access_expires_at = 1.year.from_now
  repo.active = true
  repo.metadata = {
    'go_version' => '>=1.19',
    'kubernetes' => 'required',
    'license' => 'Enterprise Commercial'
  }
end

# Starter Kit Repositories
beginner_template_repo = GithubRepository.find_or_create_by(github_id: '12345005') do |repo|
  repo.name = 'starter-template'
  repo.full_name = 'starter/web-app-template'
  repo.owner = 'starter'
  repo.description = 'Beginner-friendly web application template with best practices'
  repo.html_url = 'https://github.com/starter/web-app-template'
  repo.clone_url = 'https://github.com/starter/web-app-template.git'
  repo.ssh_url = 'git@github.com:starter/web-app-template.git'
  repo.private = true
  repo.language = 'JavaScript'
  repo.stars_count = 456
  repo.forks_count = 78
  repo.price = 5.00
  repo.currency = 'USD'
  repo.polar_product_id = ENV['POLAR_TEMPLATE_PRODUCT_ID'] || 'template_individual_test'
  repo.access_expires_at = nil
  repo.active = true
  repo.metadata = {
    'node_version' => '>=16',
    'tutorial_included' => true,
    'license' => 'Commercial'
  }
end

learning_repo = GithubRepository.find_or_create_by(github_id: '12345006') do |repo|
  repo.name = 'learning-examples'
  repo.full_name = 'starter/learning-examples'
  repo.owner = 'starter'
  repo.description = 'Comprehensive learning examples and tutorials for new developers'
  repo.html_url = 'https://github.com/starter/learning-examples'
  repo.clone_url = 'https://github.com/starter/learning-examples.git'
  repo.ssh_url = 'git@github.com:starter/learning-examples.git'
  repo.private = true
  repo.language = 'Multiple'
  repo.stars_count = 234
  repo.forks_count = 56
  repo.price = 8.00
  repo.currency = 'USD'
  repo.polar_product_id = ENV['POLAR_LEARNING_PRODUCT_ID'] || 'learning_individual_test'
  repo.access_expires_at = nil
  repo.active = true
  repo.metadata = {
    'tutorial_count' => 25,
    'difficulty' => 'beginner',
    'license' => 'Educational Commercial'
  }
end

puts "Created #{GithubRepository.count} GitHub repositories"

# Associate repositories with packages
puts "Associating repositories with packages..."

# Premium Dev Tools Package
tools_package.github_repositories = [cli_tool_repo, debug_suite_repo]

# Enterprise Package
enterprise_package.github_repositories = [microservices_repo, monitoring_repo]

# Starter Package
starter_package.github_repositories = [beginner_template_repo, learning_repo]

# Create sample users with different GitHub scenarios
puts "Creating sample users..."

# Pro developer with access to premium tools
pro_dev_user = User.find_or_create_by(email: 'github-pro@example.com') do |user|
  user.first_name = 'Pro'
  user.last_name = 'Developer'
  user.github_username = 'prodev123'
  user.github_id = 'gh_prodev_123456'
  user.github_access_token = 'ghp_example_token_for_pro_dev'
  user.github_connected_at = 1.month.ago
  user.polar_customer_id = 'cus_github_pro_test'
end

# Enterprise user with full access
enterprise_user = User.find_or_create_by(email: 'github-enterprise@example.com') do |user|
  user.first_name = 'Enterprise'
  user.last_name = 'Admin'
  user.github_username = 'enterprise_admin'
  user.github_id = 'gh_enterprise_987654'
  user.github_access_token = 'ghp_example_token_for_enterprise'
  user.github_connected_at = 6.months.ago
  user.polar_customer_id = 'cus_github_enterprise_test'
end

# Beginner user with starter kit access
beginner_user = User.find_or_create_by(email: 'github-beginner@example.com') do |user|
  user.first_name = 'New'
  user.last_name = 'Developer'
  user.github_username = 'newbie_dev'
  user.github_id = 'gh_newbie_111222'
  user.github_access_token = 'ghp_example_token_for_newbie'
  user.github_connected_at = 1.week.ago
  user.polar_customer_id = 'cus_github_beginner_test'
end

# Trial user with temporary access
trial_user = User.find_or_create_by(email: 'github-trial@example.com') do |user|
  user.first_name = 'Trial'
  user.last_name = 'User'
  user.github_username = 'trial_user'
  user.github_id = 'gh_trial_333444'
  user.github_access_token = 'ghp_example_token_for_trial'
  user.github_connected_at = 3.days.ago
  user.polar_customer_id = 'cus_github_trial_test'
end

# Create repository access records
puts "Creating repository access records..."

# Pro developer - has access to premium tools package
if pro_dev_user.repository_accesses.empty?
  tools_package.github_repositories.each do |repo|
    repo.grant_access_to_user(
      pro_dev_user,
      access_level: 'read',
      expires_at: nil, # Permanent access
      purchase_reference: "package_#{tools_package.id}",
      polar_order_id: "order_#{SecureRandom.hex(8)}",
      access_source: 'package_purchase'
    )
  end
end

# Enterprise user - has access to enterprise package + individual premium tool
if enterprise_user.repository_accesses.empty?
  enterprise_package.github_repositories.each do |repo|
    repo.grant_access_to_user(
      enterprise_user,
      access_level: 'read',
      expires_at: 1.year.from_now,
      purchase_reference: "package_#{enterprise_package.id}",
      polar_order_id: "order_#{SecureRandom.hex(8)}",
      access_source: 'package_purchase'
    )
  end
  
  # Also bought premium CLI tool individually
  cli_tool_repo.grant_access_to_user(
    enterprise_user,
    access_level: 'read',
    expires_at: nil,
    purchase_reference: "repository_#{cli_tool_repo.id}",
    polar_order_id: "order_#{SecureRandom.hex(8)}",
    access_source: 'individual_purchase'
  )
end

# Beginner user - has starter package access
if beginner_user.repository_accesses.empty?
  starter_package.github_repositories.each do |repo|
    repo.grant_access_to_user(
      beginner_user,
      access_level: 'read',
      expires_at: nil,
      purchase_reference: "package_#{starter_package.id}",
      polar_order_id: "order_#{SecureRandom.hex(8)}",
      access_source: 'package_purchase'
    )
  end
end

# Trial user - temporary access to one premium tool
if trial_user.repository_accesses.empty?
  cli_tool_repo.grant_access_to_user(
    trial_user,
    access_level: 'read',
    expires_at: 7.days.from_now,
    purchase_reference: 'trial_access',
    polar_order_id: nil,
    access_source: 'trial'
  )
end

# Create some access activity history
puts "Creating sample access activity..."

# Pro developer has been actively using repositories
pro_dev_user.repository_accesses.each do |access|
  access.update!(
    access_count: rand(25..100),
    last_accessed_at: rand(1..7).days.ago,
    invitation_accepted_at: 1.month.ago + rand(1..3).days
  )
end

# Enterprise user moderate usage
enterprise_user.repository_accesses.each do |access|
  access.update!(
    access_count: rand(10..50),
    last_accessed_at: rand(1..14).days.ago,
    invitation_accepted_at: 6.months.ago + rand(1..7).days
  )
end

# Beginner user learning actively
beginner_user.repository_accesses.each do |access|
  access.update!(
    access_count: rand(5..30),
    last_accessed_at: rand(1..3).days.ago,
    invitation_accepted_at: 1.week.ago + rand(1..2).days
  )
end

# Trial user just started
trial_user.repository_accesses.each do |access|
  access.update!(
    access_count: rand(1..5),
    last_accessed_at: rand(1..2).days.ago,
    invitation_accepted_at: 2.days.ago
  )
end

# Create some expired/revoked access examples
puts "Creating example of revoked access..."

# Create a user who lost access due to refund
refunded_user = User.find_or_create_by(email: 'github-refunded@example.com') do |user|
  user.first_name = 'Refunded'
  user.last_name = 'User'
  user.github_username = 'refunded_user'
  user.github_id = 'gh_refunded_555666'
  user.github_access_token = nil # Access token removed
  user.github_connected_at = 2.months.ago
  user.polar_customer_id = 'cus_github_refunded_test'
end

# Create revoked access record
cli_tool_repo.repository_accesses.create!(
  user: refunded_user,
  access_level: 'read',
  status: 'revoked',
  granted_at: 2.months.ago,
  expires_at: nil,
  revoked_at: 1.month.ago,
  revoked_reason: 'Purchase refunded',
  purchase_reference: "repository_#{cli_tool_repo.id}",
  polar_order_id: "order_#{SecureRandom.hex(8)}",
  access_source: 'individual_purchase',
  access_count: 15,
  last_accessed_at: 1.month.ago + 2.days
)

puts "Created sample users:"
puts "- Pro developer: #{pro_dev_user.email} (#{pro_dev_user.repository_accesses.active.count} active repositories)"
puts "- Enterprise user: #{enterprise_user.email} (#{enterprise_user.repository_accesses.active.count} active repositories)"
puts "- Beginner user: #{beginner_user.email} (#{beginner_user.repository_accesses.active.count} active repositories)"
puts "- Trial user: #{trial_user.email} (#{trial_user.repository_accesses.active.count} trial repositories)"
puts "- Refunded user: #{refunded_user.email} (#{refunded_user.repository_accesses.revoked.count} revoked repositories)"

puts "\nRepository packages:"
RepositoryPackage.all.each do |package|
  puts "- #{package.name}: $#{package.price} (#{package.github_repositories.count} repositories)"
end

puts "\nIndividual repositories:"
GithubRepository.active.each do |repo|
  puts "- #{repo.name}: $#{repo.price} (#{repo.language})"
end

puts "\nCreated #{RepositoryAccess.count} total repository access records"
puts "- Active: #{RepositoryAccess.active.count}"
puts "- Invited: #{RepositoryAccess.invited.count}"
puts "- Revoked: #{RepositoryAccess.revoked.count}"

puts "\nGitHub access control seed data complete!"
puts "You can now test the GitHub repository access scenario with these sample users and repositories."