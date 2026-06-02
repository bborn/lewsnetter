FactoryBot.define do
  factory :email_template do
    sequence(:name) { |n| "Template #{n}" }
    mjml_body { "<mjml><mj-body><mj-section><mj-column><mj-text>hello</mj-text></mj-column></mj-section></mj-body></mjml>" }
    association :team
  end
end
