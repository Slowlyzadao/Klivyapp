class CreateHelpFaqs < ActiveRecord::Migration[7.0]
  def up
    create_table :help_faqs do |t|
      t.string  :question, null: false, default: ''
      t.text    :answer,   null: false, default: ''
      t.string  :category, null: false, default: 'outro'
      t.integer :position, null: false, default: 0
      t.boolean :active,   null: false, default: true
      t.timestamps
    end

    add_index :help_faqs, :category
    add_index :help_faqs, [:active, :position]
  end

  def down
    drop_table :help_faqs
  end
end
