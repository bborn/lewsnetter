class AddPkceToOauthAccessGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_access_grants, :code_challenge, :string
    add_column :oauth_access_grants, :code_challenge_method, :string
  end
end
