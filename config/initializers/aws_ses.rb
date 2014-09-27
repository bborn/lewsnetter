require 'aws/ses'
ActionMailer::Base.add_delivery_method :ses, AWS::SES::Base, :access_key_id => ENV['SES_ACCESS_KEY'], :secret_access_key => ENV['SES_SECRET_KEY']
