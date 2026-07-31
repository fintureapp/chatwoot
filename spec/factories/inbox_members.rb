# frozen_string_literal: true

FactoryBot.define do
  factory :inbox_member do
    user { create(:user, :with_avatar) }
    inbox

    # An inbox member is always an agent of the inbox's account. Mirror that here so
    # eligibility checks in InboxAgentAvailability see a valid record.
    after(:create) do |inbox_member|
      account = inbox_member.inbox.account
      next if AccountUser.exists?(account_id: account.id, user_id: inbox_member.user_id)

      create(:account_user, account: account, user: inbox_member.user)
    end
  end
end
