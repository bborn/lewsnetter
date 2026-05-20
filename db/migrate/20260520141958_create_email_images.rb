class CreateEmailImages < ActiveRecord::Migration[8.0]
  # Email images are a permanent domain noun: once an <mj-image src> embeds
  # one of these URLs into a sent email, that image must outlive the
  # template, the campaign, and even the team. The blob lives in a
  # `public: true` Active Storage service (`email_media`) so its URL never
  # expires. See app/models/email_image.rb for the no-cascade rationale.
  def change
    create_table :email_images do |t|
      # team_id is nullable + the FK nullifies on team delete. An email
      # image MUST survive its team being destroyed — a newsletter sitting
      # in someone's inbox still references the image URL. On team delete
      # the row's team_id goes NULL; the image, its blob, and its public
      # URL all persist.
      t.references :team, null: true, foreign_key: {on_delete: :nullify}, index: true
      t.string :content_type
      t.bigint :byte_size
      t.string :original_filename

      t.timestamps
    end
  end
end
