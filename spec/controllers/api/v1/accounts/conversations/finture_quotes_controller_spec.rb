require 'rails_helper'

RSpec.describe 'Finture Quotes API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  describe 'GET /api/v1/accounts/{account.id}/conversations/<id>/finture_quote' do
    it 'retorna unauthorized sem autenticação' do
      get api_v1_account_conversation_finture_quote_url(account_id: account.id, conversation_id: conversation.display_id)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'retorna quote nula quando não há cotação' do
      get api_v1_account_conversation_finture_quote_url(account_id: account.id, conversation_id: conversation.display_id),
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['quote']).to be_nil
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/conversations/<id>/finture_quote' do
    it 'cria/atualiza a cotação (upsert) e retorna o payload' do
      patch api_v1_account_conversation_finture_quote_url(account_id: account.id, conversation_id: conversation.display_id),
            params: {
              product_type: 'saude_pme',
              total_value: 1850.0,
              data: { lives: { '0-18': 1, '59+': 1 }, city: 'Campinas' }
            },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      quote = response.parsed_body['quote']
      expect(quote['product_type']).to eq('saude_pme')
      expect(quote['lives_total']).to eq(2)
      expect(conversation.reload.custom_attributes['sdr_quote_summary']).to include('Saúde PME')
    end

    it 'rejeita payload inválido com 422' do
      patch api_v1_account_conversation_finture_quote_url(account_id: account.id, conversation_id: conversation.display_id),
            params: { product_type: 'inexistente' },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
