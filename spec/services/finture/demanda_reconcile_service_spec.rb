require 'rails_helper'

RSpec.describe Finture::DemandaReconcileService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { 'https://hub.example.test/api/v1/demandas/ingest' }
  let(:env) { { 'FINTURE_HUB_BASE_URL' => 'https://hub.example.test', 'FINTURE_HUB_INGEST_SECRET' => 'segredo-de-teste' } }
  let(:t0) { Time.zone.parse('2026-11-12T14:00:00Z') }
  let(:sent_bodies) { [] }

  around { |example| with_modified_env(env) { example.run } }

  before do
    travel_to(t0)
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional')
    create(:inbox_member, inbox: inbox, user: agent)
  end

  after { travel_back }

  def hub(motivo: nil, demanda: { id: 'hub-1' }, status: 200)
    body = { demanda: demanda, criada: false, ignorado: %w[futuro atrasado].include?(motivo), duplicado: motivo == 'duplicado', motivo: motivo }
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_hub(*responses)
    stub_request(:post, url).with { |req| sent_bodies << JSON.parse(req.body) }.to_return(*responses)
  end

  # Conversa que acabou de virar demanda (o listener síncrono cria a linha com elegivel_em).
  def demand_conversation
    conversation = create(:conversation, account: account, inbox: inbox)
    conversation.update!(assignee: agent, custom_attributes: { 'sdr_stage' => 'em_atendimento', 'sdr_next_action' => 'Ligar' })
    clear_enqueued_jobs
    conversation
  end

  def send_now(conversation)
    Finture::DemandaSyncJob.perform_now(conversation.id, Time.current.iso8601)
  end

  def reconcile(**options)
    result = nil
    perform_enqueued_jobs { result = described_class.new(**options).perform }
    result
  end

  it 'recupera um evento rejeitado como futuro com um evento novo, data corrigida e nova sequência, sem editar a conversa' do
    conversation = demand_conversation
    stub_hub(hub(motivo: 'futuro', demanda: nil), hub)
    expect(send_now(conversation)).to eq(:divergent)

    travel 2.minutes
    result = reconcile

    expect(result[:conversation_ids]).to eq([conversation.id])
    first, recovery = sent_bodies
    expect(recovery).to include('evento' => 'created', 'ocorrido_em' => '2026-11-12T14:02:00Z', 'sequencia' => 2,
                                'elegivel_em' => first['elegivel_em'])
    expect(recovery.except('ocorrido_em', 'sequencia')).to eq(first.except('ocorrido_em', 'sequencia'))
    expect(conversation.reload.finture_demanda_sync).to have_attributes(status: 'synced', recovery_state: 'recovered',
                                                                        hub_motivo: nil, hub_demanda_id: 'hub-1')
  end

  it 'reprocessar uma conversa failed atualiza o HUB uma vez, e a retentativa sai com o mesmo corpo' do
    conversation = demand_conversation
    stub_hub({ status: 401, body: '{"detail":{"code":"invalid_secret"}}' })
    expect(send_now(conversation)).to eq(:failed)

    travel 5.minutes
    stub_hub({ status: 503, body: 'ocupado' }, hub)
    reconcile

    retry_bodies = sent_bodies.drop(1)
    expect(retry_bodies.size).to eq(2)
    expect(retry_bodies.uniq.size).to eq(1)
    expect(conversation.reload.finture_demanda_sync).to have_attributes(status: 'synced', sequencia: 2, hub_demanda_id: 'hub-1')

    # Nada mais a reconciliar: a segunda execução não envia nada.
    expect(reconcile[:conversation_ids]).to be_empty
    expect(sent_bodies.size).to eq(3)
  end

  it 'seleciona failed, divergent e envios parados, em ordem e respeitando o limite do lote' do
    failed, divergent, stuck, recent, synced = Array.new(5) { demand_conversation }
    failed.finture_demanda_sync.update!(status: 'failed')
    divergent.finture_demanda_sync.update!(status: 'divergent', recovery_state: 'pending', hub_motivo: 'futuro')
    stuck.finture_demanda_sync.update_columns(status: 'retrying', updated_at: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    recent.finture_demanda_sync.update!(status: 'retrying')
    synced.finture_demanda_sync.update!(status: 'synced')

    expect(described_class.candidates.pluck(:conversation_id)).to contain_exactly(failed.id, divergent.id, stuck.id)

    result = described_class.new(limit: 2, dry_run: true).perform
    expect(result).to include(conversation_ids: [failed.id, divergent.id], enqueued: false)
    expect(enqueued_jobs).to be_empty

    described_class.new(limit: 2).perform
    expect(Finture::DemandaSyncJob).to have_been_enqueued.with(failed.id, t0.iso8601)
    expect(Finture::DemandaSyncJob).to have_been_enqueued.with(divergent.id, t0.iso8601)
    expect(enqueued_jobs.size).to eq(2)
  end

  it 'com include_drift, reenvia synced cujo conteúdo mudou sem envio, e não os que estão iguais' do
    unchanged, drifted = Array.new(2) { demand_conversation }
    stub_hub(hub)
    [unchanged, drifted].each { |conversation| send_now(conversation) }
    new_attributes = drifted.custom_attributes.merge('sdr_next_action' => 'Enviar proposta')
    drifted.update_columns(custom_attributes: new_attributes) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.new(dry_run: true).perform[:conversation_ids]).to be_empty
    expect(described_class.new(include_drift: true, dry_run: true).perform[:conversation_ids]).to eq([drifted.id])
  end

  it 'por conversa: reenvio forçado do estado atual, mesmo sem mudança, sem autor' do
    conversation = demand_conversation
    stub_hub(hub)
    send_now(conversation)

    travel 1.minute
    expect(described_class.reconcile_conversation!(conversation.id)).to eq(:updated)

    expect(sent_bodies.pluck('sequencia', 'ocorrido_em')).to eq([[1, '2026-11-12T14:00:00Z'], [2, '2026-11-12T14:01:00Z']])
    expect(sent_bodies.last).not_to have_key('autor')
  end
end
