require "rails/railtie"

module Lewsnetter
  class Railtie < ::Rails::Railtie
    initializer "lewsnetter.subscriber_concern" do
      ActiveSupport.on_load(:active_record) do
        extend Lewsnetter::Subscriber::ClassMethods
      end
    end
  end
end
