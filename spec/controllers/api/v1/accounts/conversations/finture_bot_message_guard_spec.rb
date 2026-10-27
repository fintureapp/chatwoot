require 'rails_helper'

# Trava do envio do bot (Finture::BotMessageGuard) no POST de mensagens e
# proteção do modo no POST de custom_attributes (fluxos antigos do n8n).
RSpec.describe 'Finture bot message guard', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:bot_user) { create(:user, account: account, role: :agent) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:service) { Finture::AttendanceModeService.new(conversation: conversation) }

  def send_bot_message(revision, private_note: false)
    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
         params: { content: 'Oi! Sou a Bia.', private: private_note, content_attributes: { finture_bot_revision: revision } },
         headers: bot_user.create_new_auth_token, as: :json
  end

  before do
    create(:inbox_member, inbox: inbox, user: bot_user)
    create(:inbox_member, inbox: inbox, user: agent)
  end

  describe 'POST messages' do
    it 'envia quando o modo é IA e a revisão bate' do
      expect { send_bot_message(0) }.to change(conversation.messages, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'barra a resposta se alguém assumiu depois da leitura do bot' do
      service.take_over!(user: agent)

      expect { send_bot_message(0) }.not_to change(conversation.messages.outgoing, :count)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['attendance']).to include('mode' => 'humano')
    end

    it 'barra mesmo com a revisão atual quando quem assumiu foi um humano' do
      service.take_over!(user: agent)

      send_bot_message(1)
      expect(response).to have_http_status(:conflict)
    end

    it 'permite a confirmação do handoff feito pelo próprio bot' do
      service.bot_handoff!(reason: 'Triagem')

      send_bot_message(1)
      expect(response).to have_http_status(:success)
    end

    it 'não barra nota privada' do
      service.take_over!(user: agent)

      send_bot_message(0, private_note: true)
      expect(response).to have_http_status(:success)
    end

    it 'mensagem sem revisão segue como antes (fluxo antigo)' do
      service.take_over!(user: agent)

      post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
           params: { content: 'resposta do agente' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST custom_attributes' do
    def post_attrs(attrs)
      post custom_attributes_api_v1_account_conversation_url(account_id: account.id, id: conversation.display_id),
           params: { custom_attributes: attrs }, headers: bot_user.create_new_auth_token, as: :json
    end

    it 'hash velho não desfaz o modo humano' do
      service.take_over!(user: agent)

      post_attrs({ 'modo_atendimento' => 'ia', 'produto_interesse' => 'Saude' })

      conversation.reload
      expect(conversation.custom_attributes).to include('modo_atendimento' => 'humano', 'produto_interesse' => 'Saude')
      expect(Finture::AttendanceState.for(conversation).mode).to eq('humano')
    end

    it 'handoff antigo (modo humano no hash) escala pelo serviço' do
      post_attrs({ 'modo_atendimento' => 'humano' })

      state = Finture::AttendanceState.for(conversation.reload)
      expect(state).to have_attributes(mode: 'humano', source: 'legacy_api')
      expect(conversation.label_list).to include('atendimento_humano')
    end
  end
end
