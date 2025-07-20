# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Production seeds - minimal data setup
puts "Setting up production data..."

# Only create test data in development/test environments
if Rails.env.development? || Rails.env.test?
  puts "Creating development test data..."

  # Create a test admin user
  test_admin = User.find_or_create_by!(email: "test@example.com") do |user|
    user.name = "Test Admin"
    user.password = "testpassword123"
    user.role = "admin"
    user.credits = 10000
    user.provider = "developer"
    user.uid = "test-admin"
  end

  puts "Test data created!"
  puts "Test login: test@example.com / testpassword123"
else
  puts "Production environment - no test data created"
  puts "Admins will be automatically assigned based on ADMIN_EMAILS environment variable"
end

puts "\nSeed completed!"
