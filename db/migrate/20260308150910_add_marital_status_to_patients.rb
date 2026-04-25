class AddMaritalStatusToPatients < ActiveRecord::Migration[7.1]
  def change
    add_column :patients, :marital_status, :string
  end
end
