class Notification::RemoveDuplicateNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification)
    return unless notification.is_a?(Notification)

    user_id = notification.user_id
    primary_actor_id = notification.primary_actor_id

    # Find older UNREAD notifications with the same user and primary_actor_id.
    # Read notifications are kept as history (Finture: 7-day bell history);
    # only the unread ones are collapsed so the bell shows one live item per
    # conversation.
    Notification.where(user_id: user_id, primary_actor_id: primary_actor_id, read_at: nil)
                .where.not(id: notification.id)
                .find_each(&:destroy)
  end
end
