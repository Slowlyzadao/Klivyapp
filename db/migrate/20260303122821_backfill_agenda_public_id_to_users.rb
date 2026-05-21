class BackfillAgendaPublicIdToUsers < ActiveRecord::Migration[7.1]
  def up
    User.where(agenda_public_id: nil).find_each do |user|
      user.generate_agenda_public_id
      user.save!
    end

    remove_foreign_key :agenda_events, :contacts if foreign_key_exists?(:agenda_events, :contacts)
    add_foreign_key :agenda_events, :contacts, on_delete: :nullify
  end

  def down
    remove_foreign_key :agenda_events, :contacts if foreign_key_exists?(:agenda_events, :contacts)
    add_foreign_key :agenda_events, :contacts
  end
end
