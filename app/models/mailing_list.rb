require 'heuristics'

Heuristics.define(:column_tester) do
  assume(:date_value)   { Chronic.parse(value) }
  assume(:email_value)  { value.match /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i }
  assume(:name_key)     { value.match /.*(name|login).*/i }
  assume(:email_key)    { value.match /.*e.*mail.*/i }
  assume(:created_at_key) { value.match /.*(creat|subscrib).*/i }
end

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

  def guess_csv_columns(f)

    mapping = {}

    SmarterCSV.process(f, {
      :chunk_size => 1
    }) do |rows|
      rows.each do |row|

        row.keys.each do |key|
          res = Heuristics.test(key, :column_tester)
          case res
            when :name_key
              mapping[key] = :name
            when :email_key
              mapping[key] = :email
            when :created_at_key
              mapping[key] = :created_at
          end
        end
      end

      break #just look at one chunk
    end

    return mapping
  end

  def import(file)
    path = file.path

    f =  File.open(path,  "r:bom|utf-8")
    key_mapping = guess_csv_columns(f)
    f.close

    unless key_mapping.values.include?(:email)
      return {status: :error, message: "Could not find an e-mail column in the CSV file."}
    end

    f =  File.open(path,  "r:bom|utf-8")

    begin
      n = SmarterCSV.process(f, {
        chunk_size: 100,
        key_mapping: key_mapping
        }) do |rows|

          next unless rows.first.keys.include?(:email)

          self.delay.import_rows(rows)
      end
      f.close
      {status: :ok, key_mapping: key_mapping}
    rescue CSV::MalformedCSVError
      {status: :error, message: "Error importing file: #{$!.to_s}"}
    end


  end

  def import_rows(rows)
    rows.each do |row|
      self.delay.import_row(row)
    end
  end

  def import_row(row)
    email = ActiveSupport::JSON.encode row[:email]
    name  = ActiveSupport::JSON.encode(row[:name])

    sub = Subscription.find_or_initialize_by(email: email)
    sub.created_at = DateTime.parse(row[:created_at]) if row[:created_at]
    sub.name       = name
    sub.importing  = true
    if sub.new_record?
      sub.confirmed  ||= true
      sub.subscribed ||= true
    end
    sub.save
    #don't send confirmation e-mail!!

    self.subscriptions << sub
  end

end
