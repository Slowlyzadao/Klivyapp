class AddPartialIndexForUnreadNotifications < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  # NotificationFinder default query:
  #   WHERE user_id = ? AND account_id = ?
  #     AND snoozed_until IS NULL
  #     AND read_at IS NULL
  #   ORDER BY last_activity_at DESC
  #   LIMIT 15
  #
  # Today the planner picks `idx_notifications_performance`
  # (user_id, account_id, snoozed_until, read_at) for the WHERE, then does a
  # Sort step over the matching rows because there's no covering ordering.
  # On an agent with thousands of historical notifications the Sort burns
  # 5-50ms of CPU per request and grows linearly.
  #
  # This partial composite + DESC ordering eliminates the Sort: rows come
  # out of the index already in the right order. The `WHERE read_at IS NULL
  # AND snoozed_until IS NULL` clause keeps the index tiny — typically <5%
  # of notifications are simultaneously unread AND not snoozed, so this is
  # a small index that targets the hottest read path.
  #
  # CONCURRENTLY = no table lock; safe on production. Idempotent via the
  # `if_not_exists` check.

  INDEX_NAME = :idx_notifications_unread_by_activity

  def up
    return if index_name_exists?(:notifications, INDEX_NAME)

    add_index :notifications,
              [:user_id, :account_id, :last_activity_at],
              order: { last_activity_at: :desc },
              where: 'read_at IS NULL AND snoozed_until IS NULL',
              name: INDEX_NAME,
              algorithm: :concurrently
  end

  def down
    return unless index_name_exists?(:notifications, INDEX_NAME)

    remove_index :notifications,
                 name: INDEX_NAME,
                 algorithm: :concurrently
  end
end
