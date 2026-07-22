require 'rails_helper'

RSpec.describe 'Finture Follow Ups API', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  def follow_ups_url(id = nil)
    base = api_v1_account_conversation_finture_follow_ups_url(
      account_id: account.id, conversation_id: conversation.display_id
    )
    id ? "#{base}/#{id}" : base
  end

  it 'retorna unauthorized sem autenticação' do
    get follow_ups_url
    expect(response).to have_http_status(:unauthorized)
  end

  it 'cria follow-up e espelha o próximo vencimento na conversa' do
    due_at = 2.days.from_now
    post follow_ups_url,
         params: { title: 'Ligar para o cliente', due_at: due_at.iso8601 },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['title']).to eq('Ligar para o cliente')
    expect(conversation.reload.custom_attributes['sdr_follow_up_due_at']).to eq(due_at.to_i)
  end

  it 'concluir o único follow-up remove o espelho' do
    follow_up = Finture::FollowUp.create!(
      account: account, conversation: conversation, title: 'Enviar proposta', due_at: 1.day.from_now
    )
    Finture::FollowUp.sync_mirror!(conversation)

    patch follow_ups_url(follow_up.id),
          params: { completed: true },
          headers: agent.create_new_auth_token,
          as: :json

    expect(response).to have_http_status(:success)
    expect(conversation.reload.custom_attributes).not_to have_key('sdr_follow_up_due_at')
    expect(follow_up.reload).to be_completed
  end

  it 'espelha sempre o follow-up aberto mais próximo' do
    Finture::FollowUp.create!(account: account, conversation: conversation, title: 'Depois', due_at: 5.days.from_now)
    nearest = Finture::FollowUp.create!(account: account, conversation: conversation, title: 'Antes', due_at: 1.day.from_now)
    Finture::FollowUp.sync_mirror!(conversation)

    expect(conversation.reload.custom_attributes['sdr_follow_up_due_at']).to eq(nearest.due_at.to_i)

    delete follow_ups_url(nearest.id), headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(conversation.reload.custom_attributes['sdr_follow_up_due_at']).not_to eq(nearest.due_at.to_i)
  end
end
