
# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :delivery do
    mail_campaign { FactoryGirl.create(:campaign) }
    from { Faker::Internet.email }
    to { Faker::Internet.email }
    subject "Subject Line"
    body_html "Body HTML"
    body_text "Body text"
    retries 1
    status 1
  end
end
