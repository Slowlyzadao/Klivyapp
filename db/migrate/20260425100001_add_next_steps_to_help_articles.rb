class AddNextStepsToHelpArticles < ActiveRecord::Migration[7.0]
  def change
    add_column :help_articles, :next_steps, :text
  end
end
