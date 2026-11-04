require 'rails_helper'

RSpec.describe Microsoft::OauthState do
  let(:account_state) { create(:account).to_sgid(expires_in: 15.minutes, for: 'default').to_s }

  it 'round-trips the account state and the mailbox' do
    expect(described_class.unwrap(described_class.wrap(account_state, 'comercial@finture.example')))
      .to eq([account_state, 'comercial@finture.example'])
  end

  it 'passes a plain account state through untouched' do
    expect(described_class.unwrap(account_state)).to eq([account_state, nil])
  end

  it 'does not trust a tampered state' do
    tampered = "#{described_class.wrap(account_state, 'comercial@finture.example')}x"

    expect(described_class.unwrap(tampered)).to eq([tampered, nil])
  end
end
