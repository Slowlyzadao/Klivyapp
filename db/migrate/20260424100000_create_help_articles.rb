class CreateHelpArticles < ActiveRecord::Migration[7.0]
  def change
    create_table :help_articles do |t|
      t.string   :title,     null: false
      t.text     :body
      t.string   :category,  null: false, default: 'outro'
      t.string   :status,    null: false, default: 'published'
      t.string   :video_url
      t.integer  :position,  null: false, default: 0
      t.datetime :deleted_at

      t.timestamps null: false
    end

    add_index :help_articles, :category
    add_index :help_articles, :status
    add_index :help_articles, :deleted_at
    add_index :help_articles, [:status, :category]
  end
end
