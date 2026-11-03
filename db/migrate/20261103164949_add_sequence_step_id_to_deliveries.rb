class AddSequenceStepIdToDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_reference :deliveries, :sequence_step, foreign_key: {on_delete: :nullify}, type: :integer
  end
end
