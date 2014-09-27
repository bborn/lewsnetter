class SenderAddress < ActiveRecord::Base

  after_create :ses_verify_address

  def ses
    raise 'No SES_ACCESS_KEY ENV variable is set' unless ENV['SES_ACCESS_KEY']
    raise 'No SES_SECRET_KEY ENV variable is set' unless ENV['SES_SECRET_KEY']

    ses = AWS::SES::Base.new :access_key_id => ENV['SES_ACCESS_KEY'], :secret_access_key => ENV['SES_SECRET_KEY']
  end

  def ses_verify_address
    ses.addresses.verify(self.email)
  end

  def ses_verified
    ses.addresses.list.result.include?(self.email)
  end

  rails_admin do
    list do
      field :email
      field :ses_verified, :boolean
    end
  end

end
