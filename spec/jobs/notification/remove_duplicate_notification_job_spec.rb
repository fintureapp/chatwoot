require 'rails_helper'

RSpec.describe Notification::RemoveDuplicateNotificationJob do
  let(:user) { create(:user) }
  let(:conversation) { create(:conversation) }

  it 'enqueues the job' do
    duplicate_notification = create(:notification, user: user, notification_type: 'conversation_creation', primary_actor: conversation)
    expect do
      described_class.perform_later(duplicate_notification)
    end.to have_enqueued_job(described_class)
      .on_queue('default')
  end

  it 'removes duplicate notifications' do
    create(:notification, user: user, notification_type: 'conversation_creation', primary_actor: conversation)
    duplicate_notification = create(:notification, user: user, notification_type: 'conversation_creation', primary_actor: conversation)

    described_class.perform_now(duplicate_notification)
    expect(Notification.count).to eq(1)
  end

  it 'keeps read notifications of the same conversation as history' do
    read_notification = create(:notification, user: user, notification_type: 'team_assignment', primary_actor: conversation,
                                              read_at: 1.hour.ago)
    unread_old = create(:notification, user: user, notification_type: 'conversation_assignment', primary_actor: conversation)
    latest = create(:notification, user: user, notification_type: 'assigned_conversation_new_message', primary_actor: conversation)

    described_class.perform_now(latest)

    expect(Notification.where(id: read_notification.id)).to exist
    expect(Notification.where(id: unread_old.id)).not_to exist
    expect(Notification.where(id: latest.id)).to exist
  end
end
