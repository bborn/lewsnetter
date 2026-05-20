class CreateEmailImages < ActiveRecord::Migration[8.0]
  # Email images are a permanent domain noun: once an <mj-image src> embeds
  # one of these URLs into a sent email, that image must outlive the
  # template, the campaign, and even the team. The blob lives in a
  # `public: true` Active Storage service (`email_media`) so its URL never
  # expires. See app/models/email_image.rb for the no-cascade rationale.
  def change
    create_table :email_images do |t|
      t.references :team, null: false, foreign_key: true, index: true
      t.string :content_type
      t.bigint :byte_size
      t.string :original_filename

      t.timestamps
    end
  end
end
