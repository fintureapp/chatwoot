require 'rails_helper'

# Etapas do funil por caixa. O foco aqui é o `counts_in_stage_time`: a chave que
# tira as etapas de espera do cliente do "Tempo médio na etapa" do Dashboard.
RSpec.describe 'Finture pipeline stages API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:stage) do
    Finture::PipelineStage.create!(account: account, inbox: inbox, slug: 'em_triagem',
                                   name: 'Em Triagem', color: 'blue', position: 1)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/finture_pipeline_stages/#{stage.id}" }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'exposes counts_in_stage_time on index' do
    get "/api/v1/accounts/#{account.id}/finture_pipeline_stages",
        params: { inbox_id: inbox.id }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].map { |row| row['counts_in_stage_time'] }).to all(be(true))
  end

  it 'lets an admin switch the stage off' do
    patch url, params: { inbox_id: inbox.id, counts_in_stage_time: false },
               headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['stage']['counts_in_stage_time']).to be(false)
    expect(stage.reload.counts_in_stage_time).to be(false)
  end

  it 'keeps the flag untouched when the request only renames the stage' do
    stage.update!(counts_in_stage_time: false)

    patch url, params: { inbox_id: inbox.id, name: 'Triagem' },
               headers: admin.create_new_auth_token, as: :json

    expect(stage.reload).to have_attributes(name: 'Triagem', counts_in_stage_time: false)
  end

  it 'refuses an agent' do
    patch url, params: { inbox_id: inbox.id, counts_in_stage_time: false },
               headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(stage.reload.counts_in_stage_time).to be(true)
  end
end
