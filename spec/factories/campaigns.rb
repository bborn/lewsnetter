FactoryGirl.define do
  factory :campaign do
    subject 'Test Email Campaign'
    mailing_list { FactoryGirl.create(:mailing_list) }
    from 'test@example.com'
  end
end
