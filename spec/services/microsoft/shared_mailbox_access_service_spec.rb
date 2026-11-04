require 'rails_helper'

RSpec.describe Microsoft::SharedMailboxAccessService do
  subject(:service) { described_class.new(mailbox: 'comercial@finture.example', access_token: 'token') }

  let(:imap) { instance_double(Net::IMAP, logout: nil, disconnect: nil, disconnected?: false) }

  before do
    allow(Net::IMAP).to receive(:new).with('outlook.office365.com', port: 993, ssl: true, open_timeout: 15).and_return(imap)
  end

  it 'opens the shared mailbox read-only as the mailbox itself' do
    allow(imap).to receive(:authenticate)
    allow(imap).to receive(:examine)

    expect(service.accessible?).to be true
    expect(imap).to have_received(:authenticate).with('XOAUTH2', 'comercial@finture.example', 'token')
    expect(imap).to have_received(:examine).with('INBOX')
    expect(imap).to have_received(:logout)
  end

  it 'reports no access when Exchange rejects the delegation' do
    response = Net::IMAP::TaggedResponse.new('RUBY0001', 'NO', Net::IMAP::ResponseText.new(nil, 'AUTHENTICATE failed.'), '')
    allow(imap).to receive(:authenticate).and_raise(Net::IMAP::NoResponseError.new(response))

    expect(service.accessible?).to be false
    expect(imap).to have_received(:disconnect)
  end
end
