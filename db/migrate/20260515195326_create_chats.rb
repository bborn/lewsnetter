class CreateChats < ActiveRecord::Migration[8.1]
  def change
    create_table :chats do |t|
      t.references :team, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.string :title
      t.timestamps
    end
    add_index :chats, [:team_id, :user_id]
  end
end
