require 'rails_helper'

# Configuração Finture da caixa: aqui o foco é o toggle de transcrição de áudio.
RSpec.describe 'Finture inbox config API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/finture_inbox_config" }

  it 'mostra a transcrição desligada em caixa sem configuração' do
    get url, params: { inbox_id: inbox.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('kanban_type' => 'comercial', 'ai_enabled' => false,
                                            'audio_transcription_enabled' => false)
  end

  it 'liga a transcrição sem mexer no tipo nem na IA' do
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional', ai_enabled: true)

    put url, params: { inbox_id: inbox.id, audio_transcription_enabled: true }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('kanban_type' => 'operacional', 'ai_enabled' => true,
                                            'audio_transcription_enabled' => true)
    expect(Finture::InboxConfig.audio_transcription?(inbox.id)).to be(true)
  end

  it 'não deixa agente alterar' do
    put url, params: { inbox_id: inbox.id, audio_transcription_enabled: true }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
