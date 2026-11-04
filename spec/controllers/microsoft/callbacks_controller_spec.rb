require 'rails_helper'

RSpec.describe 'Microsoft::CallbacksController', type: :request do
  let(:account) { create(:account) }
  let(:code) { SecureRandom.hex(10) }
  let(:email) { Faker::Internet.email }
  let(:state) { account.to_sgid(expires_in: 15.minutes).to_s }

  describe 'GET /microsoft/callback' do
    let(:response_body_success) do
      { id_token: JWT.encode({ email: email, name: 'test' }, nil, 'none'), access_token: SecureRandom.hex(10), token_type: 'Bearer',
        refresh_token: SecureRandom.hex(10) }
    end

    let(:response_body_success_without_name) do
      { id_token: JWT.encode({ email: email }, nil, 'none'), access_token: SecureRandom.hex(10), token_type: 'Bearer',
        refresh_token: SecureRandom.hex(10) }
    end

    it 'creates inboxes if authentication is successful' do
      stub_request(:post, 'https://login.microsoftonline.com/common/oauth2/v2.0/token')
        .with(body: { 'code' => code, 'grant_type' => 'authorization_code',
                      'redirect_uri' => "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/microsoft/callback" })
        .to_return(status: 200, body: response_body_success.to_json, headers: { 'Content-Type' => 'application/json' })

      get microsoft_callback_url, params: { code: code, state: state }

      expect(response).to redirect_to app_email_inbox_agents_url(account_id: account.id, inbox_id: account.inboxes.last.id)
      expect(account.inboxes.count).to be 1
      inbox = account.inboxes.last
      expect(inbox.name).to eq 'test'
      expect(inbox.channel.reload.provider_config.keys).to include('access_token', 'refresh_token', 'expires_on')
      expect(inbox.channel.reload.provider_config['access_token']).to eq response_body_success[:access_token]
      expect(inbox.channel.imap_address).to eq 'outlook.office365.com'
    end

    it 'sets imap_login from preferred_username when the id_token carries a UPN that differs from email' do
      upn = 'testaccount@primary-domain.example'
      mailbox = 'TestAccount@mailbox-domain.example'
      response_body = {
        id_token: JWT.encode({ email: mailbox, preferred_username: upn, name: 'test' }, nil, 'none'),
        access_token: SecureRandom.hex(10), token_type: 'Bearer', refresh_token: SecureRandom.hex(10)
      }
      stub_request(:post, 'https://login.microsoftonline.com/common/oauth2/v2.0/token')
        .with(body: { 'code' => code, 'grant_type' => 'authorization_code',
                      'redirect_uri' => "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/microsoft/callback" })
        .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })

      get microsoft_callback_url, params: { code: code, state: state }

      channel = account.inboxes.last.channel
      expect(channel.imap_login).to eq upn
      expect(channel.email).to eq mailbox
    end

    it 'creates updates inbox channel config if inbox exists and authentication is successful' do
      inbox = create(:channel_email, account: account, email: email)&.inbox
      expect(inbox.channel.provider_config).to eq({})

      stub_request(:post, 'https://login.microsoftonline.com/common/oauth2/v2.0/token')
        .with(body: { 'code' => code, 'grant_type' => 'authorization_code',
                      'redirect_uri' => "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/microsoft/callback" })
        .to_return(status: 200, body: response_body_success.to_json, headers: { 'Content-Type' => 'application/json' })

      get microsoft_callback_url, params: { code: code, state: state }

      expect(response).to redirect_to app_email_inbox_settings_url(account_id: account.id, inbox_id: account.inboxes.last.id)
      expect(account.inboxes.count).to be 1
      expect(inbox.channel.reload.provider_config.keys).to include('access_token', 'refresh_token', 'expires_on')
      expect(inbox.channel.reload.provider_config['access_token']).to eq response_body_success[:access_token]
      expect(inbox.channel.imap_address).to eq 'outlook.office365.com'
    end

    it 'creates inboxes with fallback_name when account name is not present in id_token' do
      stub_request(:post, 'https://login.microsoftonline.com/common/oauth2/v2.0/token')
        .with(body: { 'code' => code, 'grant_type' => 'authorization_code',
                      'redirect_uri' => "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/microsoft/callback" })
        .to_return(status: 200, body: response_body_success_without_name.to_json, headers: { 'Content-Type' => 'application/json' })

      get microsoft_callback_url, params: { code: code, state: state }

      expect(response).to redirect_to app_email_inbox_agents_url(account_id: account.id, inbox_id: account.inboxes.last.id)
      expect(account.inboxes.count).to be 1
      inbox = account.inboxes.last
      expect(inbox.name).to eq email.split('@').first.parameterize.titleize
    end

    context 'when connecting a shared mailbox' do
      let(:shared_mailbox) { 'comercial@finture.example' }
      let(:delegate_upn) { 'pedro.vanini@criteria.example' }
      let(:state) { Microsoft::OauthState.wrap(account.to_sgid(expires_in: 15.minutes, for: 'default').to_s, shared_mailbox) }
      let(:access_service) { instance_double(Microsoft::SharedMailboxAccessService, accessible?: true) }
      let(:response_body) do
        { id_token: JWT.encode({ email: delegate_upn, preferred_username: delegate_upn, name: 'Pedro Vanini' }, nil, 'none'),
          access_token: SecureRandom.hex(10), token_type: 'Bearer', refresh_token: SecureRandom.hex(10) }
      end

      before do
        stub_request(:post, 'https://login.microsoftonline.com/common/oauth2/v2.0/token')
          .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
        allow(Microsoft::SharedMailboxAccessService).to receive(:new)
          .with(mailbox: shared_mailbox, access_token: response_body[:access_token]).and_return(access_service)
      end

      it 'creates the inbox for the shared mailbox, reading it as the mailbox and sending as the delegate' do
        get microsoft_callback_url, params: { code: code, state: state }

        inbox = account.inboxes.last
        expect(response).to redirect_to app_email_inbox_agents_url(account_id: account.id, inbox_id: inbox.id)
        expect(inbox.name).to eq 'Comercial'
        expect(inbox.channel.email).to eq shared_mailbox
        expect(inbox.channel.imap_login).to eq shared_mailbox
        expect(inbox.channel.smtp_login).to eq delegate_upn
        expect(inbox.channel.provider).to eq 'microsoft'
      end

      it 'reauthorizes the existing shared mailbox inbox instead of creating another one' do
        existing = create(:channel_email, account: account, email: shared_mailbox)

        get microsoft_callback_url, params: { code: code, state: state }

        expect(response).to redirect_to app_email_inbox_settings_url(account_id: account.id, inbox_id: existing.inbox.id)
        expect(account.inboxes.count).to be 1
        expect(existing.reload.imap_login).to eq shared_mailbox
        expect(existing.provider_config['access_token']).to eq response_body[:access_token]
      end

      it 'does not create an inbox when the signed-in identity cannot open the shared mailbox' do
        allow(access_service).to receive(:accessible?).and_return(false)

        get microsoft_callback_url, params: { code: code, state: state }

        expect(response).to redirect_to app_new_email_inbox_url(account_id: account.id, provider: 'microsoft',
                                                                error: 'shared_mailbox_access', mailbox: shared_mailbox)
        expect(account.inboxes.count).to be 0
      end

      it 'treats the signed-in mailbox as a regular inbox when it is the requested one' do
        own_state = Microsoft::OauthState.wrap(account.to_sgid(expires_in: 15.minutes, for: 'default').to_s, delegate_upn.upcase)

        get microsoft_callback_url, params: { code: code, state: own_state }

        channel = account.inboxes.last.channel
        expect(Microsoft::SharedMailboxAccessService).not_to have_received(:new)
        expect(channel.email).to eq delegate_upn
        expect(channel.imap_login).to eq delegate_upn
        expect(account.inboxes.last.name).to eq 'Pedro Vanini'
      end
    end

    it 'redirects to microsoft app in case of error' do
      stub_request(:post, 'https://login.microsoftonline.com/common/oauth2/v2.0/token')
        .with(body: { 'code' => code, 'grant_type' => 'authorization_code',
                      'redirect_uri' => "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/microsoft/callback" })
        .to_return(status: 401)

      get microsoft_callback_url, params: { code: code, state: state }

      expect(response).to redirect_to '/'
    end
  end
end
