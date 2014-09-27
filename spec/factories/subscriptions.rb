# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :subscription do
    email { Faker::Internet.email }
    name  { Faker::Name.first_name }
    subscribed true
    confirmed true
  end
end
