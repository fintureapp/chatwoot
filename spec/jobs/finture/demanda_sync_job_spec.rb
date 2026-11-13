require 'rails_helper'

RSpec.describe Finture::DemandaSyncJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { 'https://hub.test/api/v1/demandas/ingest' }
  let(:env) { { 'FINTURE_HUB_BASE_URL' => 'https://hub.test', 'FINTURE_HUB_INGEST_SECRET' => 'segredo' } }

  around { |example| with_modified_env(env) { example.run } }

  before do
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional')
    conversation.update!(assignee: agent, custom_attributes: { 'sdr_stage' => 'em_atendimento' })
  end

  it 'envia a demanda e grava o id do HUB' do
    stub_request(:post, url).to_return(status: 201, body: { demanda: { id: 'hub-9' } }.to_json)

    perform_enqueued_jobs { described_class.perform_later(conversation.id, Time.current.iso8601) }

    expect(conversation.reload.finture_demanda_sync).to have_attributes(status: 'synced', hub_demanda_id: 'hub-9')
  end

  it 'tenta de novo em erro passageiro e marca failed ao esgotar' do
    stub_request(:post, url).to_return(status: 503, body: 'fora do ar')

    perform_enqueued_jobs { described_class.perform_later(conversation.id, Time.current.iso8601) }

    expect(WebMock).to have_requested(:post, url).times(6)
    sync = conversation.reload.finture_demanda_sync
    expect(sync.status).to eq('failed')
    expect(sync.last_error).to include('tentativas esgotadas')
  end

  it 'descarta conversa inexistente' do
    expect { described_class.perform_now(0, Time.current.iso8601) }.not_to raise_error
    expect(WebMock).not_to have_requested(:post, url)
  end

  it 'aceita chamada sem horário (reprocessamento manual)' do
    stub_request(:post, url).to_return(status: 201, body: { demanda: { id: 'hub-1' } }.to_json)
    expect(described_class.perform_now(conversation.id)).to eq(:created)
  end
end
