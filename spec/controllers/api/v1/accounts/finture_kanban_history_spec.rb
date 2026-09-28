require 'rails_helper'

# Aba Histórico do Kanban SDR (conversations#kanban_history). A action é de
# coleção (não recebe :id) e precisa ficar fora do before_action :conversation,
# senão responde 404 e a UI mostra "0 demandas" silenciosamente.
RSpec.describe 'Kanban SDR history API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/kanban_history" }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  context 'when the inbox is commercial (default)' do
    it 'returns only leads closed with an outcome' do
      won = create(:conversation, account: account, inbox: inbox,
                                  custom_attributes: { 'sdr_outcome' => 'won', 'sdr_outcome_at' => Time.now.to_i })
      create(:conversation, account: account, inbox: inbox, status: :resolved)

      get url, params: { inbox_id: inbox.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      ids = response.parsed_body['payload'].map { |c| c['id'] }
      expect(ids).to eq([won.display_id])
    end
  end

  context 'when the inbox is operational' do
    before { Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional') }

    it 'returns the resolved conversations with their AI summary' do
      resolved = create(:conversation, account: account, inbox: inbox, status: :resolved,
                                       custom_attributes: { 'sdr_resumo' => 'Cliente pediu 2ª via.' })
      create(:conversation, account: account, inbox: inbox, status: :open)

      get url, params: { inbox_id: inbox.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.map { |c| c['id'] }).to eq([resolved.display_id])
      expect(payload.first['custom_attributes']['sdr_resumo']).to eq('Cliente pediu 2ª via.')
    end
  end
end
