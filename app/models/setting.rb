class Setting < Smailer::Models::Property

  def self.get_with_default(name, default)
    return self.get(name) || default
  end

  rails_admin do
  end

end
