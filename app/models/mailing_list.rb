class MailingList < Smailer::Models::MailingList

  has_and_belongs_to_many :subscriptions, -> { uniq }
  has_many :campaigns, inverse_of: :mailing_list, dependent: :destroy
  attr_accessor :csv_file

  def subscribers
    active_subscriptions
  end

  def active_subscriptions
    subscriptions.subscribed.confirmed
  end

  def import(file)
    path = file.path
    f =  File.open(path,  "r:bom|utf-8")

    begin
      n = SmarterCSV.process(f, {
        :chunk_size => 100
        }) do |rows|
          next unless rows.first.keys.include?(:email)

          self.delay.import_rows(rows)
      end
      {status: :ok}
    rescue CSV::MalformedCSVError
      {status: :error, message: "Error importing file: #{$!.to_s}"}
    end
  end

  def import_rows(rows)
    rows.each do |row|
      sub = Subscription.find_or_initialize_by(email: row[:email])
      sub.created_at = DateTime.parse(row[:created_at]) if row[:created_at]
      sub.name       = row[:name]
      sub.importing  = true
      sub.confirmed  ||= true
      sub.subscribed ||= true
      sub.save
      #don't send confirmation e-mail!!

      self.subscriptions << sub
    end
  end

end
