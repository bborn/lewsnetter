# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :sender_address do
    email "MyString"
    verified false
  end
end
