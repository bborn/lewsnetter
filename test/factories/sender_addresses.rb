FactoryBot.define do
  factory :sender_address do
    association :team
    email { "MyString" }
    name { "MyString" }
    verified { false }
    ses_status { "MyString" }
  end
end
