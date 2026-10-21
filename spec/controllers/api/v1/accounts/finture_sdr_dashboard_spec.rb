require 'rails_helper'

# Dashboard SDR (finture_sdr_dashboard#show). Trava o acesso por caixa — o
# agente só vê o que o Kanban mostraria a ele — e o fuso dos buckets diários.
RSpec.describe 'Finture SDR dashboard API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/finture_sdr_dashboard" }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe 'acesso por caixa' do
    it 'forbids an agent from asking for an inbox they do not belong to' do
      get url, params: { view: 'operational', inbox_id: other_inbox.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'lets an agent read their own inbox' do
      get url, params: { view: 'operational', inbox_id: inbox.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'lets an administrator read any inbox' do
      get url, params: { view: 'commercial', inbox_id: other_inbox.id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'leaves other inboxes out of the overall view for an agent' do
      create(:conversation, account: account, inbox: inbox)
      create(:conversation, account: account, inbox: other_inbox)

      get url, params: { view: 'commercial' }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('kpis', 'leads', 'value')).to eq(1)
    end
  end

  describe 'fuso horário' do
    # 22h30 em Brasília = 01h30 UTC do dia seguinte. No fuso do navegador o
    # lead cai no dia 20/10, não no 21/10.
    it 'buckets the daily trend in the browser time zone' do
      since = Time.utc(2026, 10, 15, 3).to_i
      until_at = Time.utc(2026, 10, 22, 3).to_i
      conv = create(:conversation, account: account, inbox: inbox)
      conv.update_columns(created_at: Time.utc(2026, 10, 21, 1, 30)) # rubocop:disable Rails/SkipsModelValidations

      get url, params: { view: 'commercial', since: since, until: until_at, timezone: 'America/Sao_Paulo' },
               headers: admin.create_new_auth_token, as: :json

      buckets = response.parsed_body.dig('trend', 'buckets')
      expect(buckets.find { |bucket| bucket['leads'] == 1 }['label']).to eq('20/10')
    end
  end
end
