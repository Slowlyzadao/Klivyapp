class AddSocialNameToPatients < ActiveRecord::Migration[7.1]
  def change
    add_column :patients, :social_name, :string
  end
end
