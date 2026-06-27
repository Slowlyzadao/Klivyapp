class AddPartialIndexOnTaggingsForLabelFilter < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  # `ConversationFinder#filter_by_labels` calls `acts_as_taggable_on`'s
  # `tagged_with(labels, any: true)`, which produces:
  #
  #   SELECT taggings.taggable_id FROM taggings
  #   WHERE taggings.tag_id IN (?, ?)
  #     AND taggings.taggable_type = 'Conversation'
  #     AND taggings.context = 'labels'
  #
  # The same shape is used by Contact label filtering (both models include
  # `Labelable`, which does `acts_as_taggable_on :labels` — context 'labels'
  # is the ONLY context Chatwoot uses).
  #
  # Today the planner picks `index_taggings_on_tag_id` (single column) and
  # then has to Filter every matching row by `taggable_type` + `context`.
  # In an account with high label usage the taggings table can hold
  # hundreds of thousands of rows, and most of them are 'labels' context
  # spread across Conversations and Contacts — the per-tag bitmap heap
  # scan becomes the bottleneck of the label filter.
  #
  # A composite `(tag_id, taggable_type)` index partial-filtered by
  # `context = 'labels'` is the smallest possible covering index for this
  # query: it pre-narrows by the only context the app uses, then provides
  # the join order the planner needs (tag_id → taggable_type → taggable_id).
  # Stays small because we only index the 'labels' subset, never touching
  # any future contexts plugins might introduce.
  #
  # CONCURRENTLY = no table lock; safe to deploy.

  INDEX_NAME = :idx_taggings_tag_type_for_label_filter

  def up
    return if index_name_exists?(:taggings, INDEX_NAME)

    add_index :taggings,
              [:tag_id, :taggable_type],
              where: "context = 'labels'",
              name: INDEX_NAME,
              algorithm: :concurrently
  end

  def down
    return unless index_name_exists?(:taggings, INDEX_NAME)

    remove_index :taggings,
                 name: INDEX_NAME,
                 algorithm: :concurrently
  end
end
