require 'rails_helper'

RSpec.describe Finture::DemandaSyncJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Agente Exemplo', email: 'agente@example.test') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { 'https://hub.example.test/api/v1/demandas/ingest' }
  let(:env) { { 'FINTURE_HUB_BASE_URL' => 'https://hub.example.test', 'FINTURE_HUB_INGEST_SECRET' => 'segredo-de-teste' } }
  let(:sent_bodies) { [] }

  around { |example| with_modified_env(env) { example.run } }

  before do
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional')
    create(:inbox_member, inbox: inbox, user: agent)
    conversation.update!(assignee: agent, custom_attributes: { 'sdr_stage' => 'em_atendimento' })
    clear_enqueued_jobs
  end

  def stub_hub(*responses)
    stub_request(:post, url).with { |req| sent_bodies << JSON.parse(req.body) }.to_return(*responses)
  end

  it 'envia a demanda com o autor do evento e grava o id do HUB' do
    stub_hub({ status: 201, body: { demanda: { id: 'hub-9' } }.to_json })

    perform_enqueued_jobs { described_class.perform_later(conversation.id, Time.current.iso8601, agent.id) }

    expect(conversation.reload.finture_demanda_sync).to have_attributes(status: 'synced', hub_demanda_id: 'hub-9')
    expect(sent_bodies.last['autor']).to eq('email' => 'agente@example.test', 'nome' => 'Agente Exemplo')
  end

  it 'tenta de novo em erro passageiro com o mesmo corpo e marca failed ao esgotar' do
    stub_hub({ status: 503, body: 'fora do ar' })

    perform_enqueued_jobs { described_class.perform_later(conversation.id, Time.current.iso8601) }

    expect(WebMock).to have_requested(:post, url).times(6)
    expect(sent_bodies.uniq.size).to eq(1)
    sync = conversation.reload.finture_demanda_sync
    expect(sync).to have_attributes(status: 'failed', sequencia: 1)
    expect(sync.last_error).to include('tentativas esgotadas')
  end

  it 'esgotar as tentativas encerra a recuperação em aberto como failed' do
    conversation.finture_demanda_sync.update!(status: 'divergent', hub_motivo: 'futuro', recovery_state: 'pending')
    stub_hub({ status: 503, body: 'fora do ar' })

    perform_enqueued_jobs { described_class.perform_later(conversation.id, Time.current.iso8601) }

    expect(conversation.reload.finture_demanda_sync).to have_attributes(status: 'failed', recovery_state: 'failed', hub_motivo: 'futuro')
  end

  it 'descarta conversa inexistente' do
    expect { described_class.perform_now(0, Time.current.iso8601) }.not_to raise_error
    expect(WebMock).not_to have_requested(:post, url)
  end

  it 'aceita os argumentos do v1 (sem autor) e chamada sem horário (reprocessamento manual)' do
    stub_hub({ status: 201, body: { demanda: { id: 'hub-1' } }.to_json })

    expect(described_class.perform_now(conversation.id)).to eq(:created)
    expect(described_class.perform_now(conversation.id, Time.current.iso8601)).to eq(:unchanged)
    expect(described_class.perform_now(conversation.id, Time.current.iso8601, nil, true)).to eq(:updated)
    expect(sent_bodies.size).to eq(2)
    expect(sent_bodies.last).not_to have_key('autor')
  end
end
