class AddMoreExampleFieldsToTangibleThings < ActiveRecord::Migration[6.1]
  def change
    add_column :scaffolding_completely_concrete_tangible_things, :date_and_time_field_value, :datetime
    add_column :scaffolding_completely_concrete_tangible_things, :multiple_button_values, :json, default: []
    add_column :scaffolding_completely_concrete_tangible_things, :multiple_super_select_values, :json, default: []
  end
end
