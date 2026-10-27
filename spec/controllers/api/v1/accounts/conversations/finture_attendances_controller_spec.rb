require 'rails_helper'

RSpec.describe 'Finture Attendance API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }

  def url(action = nil)
    base = { account_id: account.id, conversation_id: conversation.display_id }
    return api_v1_account_conversation_finture_attendance_url(**base) if action.nil?

    send("#{action}_api_v1_account_conversation_finture_attendance_url", **base)
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'comercial', ai_enabled: true)
  end

  it 'exige acesso à conversa' do
    post url(:take_over), headers: outsider.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'mostra o estado atual' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['attendance']).to include('mode' => 'ia', 'revision' => 0, 'ai_enabled' => true)
  end

  it 'assume a conversa' do
    post url(:take_over), params: { expected_revision: 0 }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['attendance']).to include('mode' => 'humano', 'revision' => 1)
    expect(response.parsed_body['assignee_id']).to eq(agent.id)
  end

  it 'devolve 409 com o estado atual quando a revisão ficou velha' do
    Finture::AttendanceModeService.new(conversation: conversation).take_over!(user: agent)

    post url(:take_over), params: { expected_revision: 0 }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['attendance']).to include('mode' => 'humano', 'revision' => 1)
    expect(response.parsed_body['error']).to be_present
  end

  it 'devolve à IA com motivo e recusa sem motivo' do
    Finture::AttendanceModeService.new(conversation: conversation).take_over!(user: agent)

    post url(:return_to_ai), params: { reason: '' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post url(:return_to_ai), params: { reason: 'só dúvida', pending_notes: 'mandar link' },
                             headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['attendance']).to include('mode' => 'ia')
    expect(conversation.reload.assignee).to be_nil
  end

  it 'registra o handoff do bot e devolve a revisão para a confirmação' do
    post url(:bot_handoff), params: { reason: 'Triagem', triage: { tipo: 'indicacao', produto: 'saude' } },
                            headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['attendance']).to include('mode' => 'humano', 'revision' => 1, 'changed_by_type' => 'bot')
  end
end
