class CreateHelpArticles < ActiveRecord::Migration[7.1]
  def change
    create_table :help_articles do |t|
      t.string :title, null: false
      t.text :body
      t.string :category, null: false
      t.string :status, null: false, default: 'draft'
      t.string :video_url
      t.text :next_steps
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :help_articles, :category
    add_index :help_articles, :status
    add_index :help_articles, :deleted_at
    add_index :help_articles, [:category, :position]
  end
end
