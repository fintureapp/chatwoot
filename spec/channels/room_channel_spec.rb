require 'rails_helper'

RSpec.describe RoomChannel do
  let!(:contact_inbox) { create(:contact_inbox) }
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }

  before do
    stub_connection
  end

  it 'subscribes to a stream when pubsub_token is provided' do
    subscribe(pubsub_token: contact_inbox.pubsub_token)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(contact_inbox.pubsub_token)
  end

  it 'subscribes to a stream when pubsub_token is provided for user' do
    subscribe(user_id: user.id, pubsub_token: user.pubsub_token, account_id: account.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(user.pubsub_token)
    expect(subscription).to have_stream_for("account_#{account.id}")
  end

  it 'tracks the user presence in redis on subscribe' do
    subscribe(user_id: user.id, pubsub_token: user.pubsub_token, account_id: account.id)
    expect(::OnlineStatusTracker.get_presence(account.id, 'User', user.id)).to be_truthy
  end

  describe 'server-side presence heartbeat' do
    it 'registers a periodic timer that renews presence while connected' do
      expect(described_class.periodic_timers.map { |callback, _options| callback }).to include(:refresh_presence)
    end

    it 'renews the presence when the periodic timer fires' do
      subscribe(user_id: user.id, pubsub_token: user.pubsub_token, account_id: account.id)

      travel_to(15.seconds.from_now) do
        subscription.send(:refresh_presence)
        expect(::OnlineStatusTracker.get_presence(account.id, 'User', user.id)).to be_truthy
      end
    end
  end
end
