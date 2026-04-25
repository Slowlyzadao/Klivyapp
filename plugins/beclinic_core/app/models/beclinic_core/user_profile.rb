module BeclinicCore
  class UserProfile < ApplicationRecord
    self.table_name = 'beclinic_user_profiles'
    belongs_to :user
  end
end
