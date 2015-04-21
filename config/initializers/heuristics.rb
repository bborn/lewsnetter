require 'heuristics'

Heuristics.define(:column_tester) do
  assume(:date_value)   { Chronic.parse(value) }
  assume(:email_value)  { value.match /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i }
  assume(:name_key)     { value.match /.*(name|login).*/i }
  assume(:email_key)    { value.match /.*e.*mail.*/i }
  assume(:created_at_key) { value.match /.*(date|creat|subscrib).*/i }
end

