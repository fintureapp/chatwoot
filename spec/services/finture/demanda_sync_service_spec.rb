require 'rails_helper'

RSpec.describe Finture::DemandaSyncService do
  let(:account) { create(:account) }
  # Sem atribuição automática: a elegibilidade depende de QUEM atribui o responsável.
  let(:inbox) { create(:inbox, account: account, name: 'OPERACIONAL-Caixa Exemplo', enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Agente Exemplo', email: 'Agente.Exemplo@example.test') }
  let(:operator) { create(:user, account: account, role: :agent, name: 'Operadora Exemplo', email: 'operadora@example.test') }
  let(:team) { create(:team, account: account, name: 'Atendimento Exemplo') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { 'https://hub.example.test/api/v1/demandas/ingest' }
  let(:env) do
    { 'FINTURE_HUB_BASE_URL' => 'https://hub.example.test', 'FINTURE_HUB_INGEST_SECRET' => 'segredo-de-teste',
      'FRONTEND_URL' => 'https://chat.example.test', 'FINTURE_HUB_PAYLOAD_VERSION' => nil }
  end
  let(:t0) { Time.zone.parse('2026-11-12T14:00:00Z') }
  let(:sent_bodies) { [] }

  around { |example| with_modified_env(env) { example.run } }

  before do
    travel_to(t0)
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional')
    # O responsável precisa ser membro da caixa e do time, senão o AssignmentHandler o remove.
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    stub_hub(hub_body)
  end

  after { travel_back }

  def hub_body(demanda: { id: 'hub-1' }, motivo: nil, ignorado: false)
    { demanda: demanda, criada: demanda.present? && motivo.nil?, ignorado: ignorado, duplicado: motivo == 'duplicado', motivo: motivo }
  end

  def stub_hub(*bodies)
    responses = bodies.map { |body| { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } } }
    stub_request(:post, url).with { |req| sent_bodies << JSON.parse(req.body) }.to_return(*responses)
  end

  def service(at: Time.current, actor: nil, force: nil)
    described_class.new(conversation: conversation.reload, occurred_at: at, actor: actor, force: force)
  end

  def sync
    conversation.reload.finture_demanda_sync
  end

  # A mudança passa pelo Finture::DemandaListener (síncrono), que registra elegivel_em = agora.
  def put_in_attendance(extra = {})
    conversation.update!(assignee: agent, team: team,
                         custom_attributes: { 'sdr_stage' => 'em_atendimento', 'sdr_next_action' => 'Ligar para o cliente',
                                              'sdr_resumo_ia' => 'Cliente quer portfólio.', 'produto_interesse' => 'Consórcio' }.merge(extra))
  end

  def change_plan(text)
    conversation.update!(custom_attributes: conversation.reload.custom_attributes.merge('sdr_next_action' => text))
  end

  it 'cria a demanda com o payload v2 quando a conversa está em Em atendimento com responsável' do
    put_in_attendance
    travel 3.minutes

    expect(service.perform).to eq(:created)

    expect(sync).to have_attributes(status: 'synced', hub_demanda_id: 'hub-1', last_event: 'created', attempts: 1, sequencia: 1,
                                    hub_motivo: nil, recovery_state: nil, external_id: "chatwoot:#{account.id}:#{conversation.display_id}")
    body = sent_bodies.last
    expect(body).to include(
      'origem' => 'chatwoot', 'evento' => 'created', 'payload_version' => 2, 'sequencia' => 1,
      'external_id' => "chatwoot:#{account.id}:#{conversation.display_id}", 'titulo' => "#{conversation.contact.name} — Consórcio",
      'contexto' => 'Cliente quer portfólio.', 'plano_acao' => 'Ligar para o cliente', 'resumo_final' => nil,
      'responsavel_email' => 'agente.exemplo@example.test', 'responsavel_nome' => 'Agente Exemplo',
      'time' => 'atendimento exemplo', 'canal' => 'WebWidget', 'etapa' => 'em_atendimento', 'status_origem' => 'open',
      'produto_interesse' => 'Consórcio', 'ocorrido_em' => '2026-11-12T14:03:00Z',
      'conversa_criada_em' => '2026-11-12T14:00:00Z', 'elegivel_em' => '2026-11-12T14:00:00Z',
      'link' => "https://chat.example.test/app/accounts/#{account.id}/conversations/#{conversation.display_id}"
    )
    expect(body).not_to have_key('autor')
    expect(body['caixa']).to eq('id' => inbox.id, 'nome' => 'OPERACIONAL-Caixa Exemplo')
    expect(WebMock).to have_requested(:post, url).with(headers: { 'X-Ingest-Secret' => 'segredo-de-teste' }).once
  end

  it 'envia autor só quando um usuário fez a mudança, nunca o responsável no lugar' do
    put_in_attendance
    service(actor: operator).perform
    expect(sent_bodies.last['autor']).to eq('email' => 'operadora@example.test', 'nome' => 'Operadora Exemplo')

    change_plan('Enviar proposta')
    service(actor: nil).perform
    expect(sent_bodies.last).not_to have_key('autor')
    expect(sent_bodies.last['responsavel_email']).to eq('agente.exemplo@example.test')
  end

  it 'omite elegivel_em quando o instante não foi registrado, sem aproximar' do
    put_in_attendance
    sync.update!(elegivel_em: nil)

    service.perform

    expect(sent_bodies.last).not_to have_key('elegivel_em')
    expect(sent_bodies.last).to include('conversa_criada_em' => '2026-11-12T14:00:00Z')
  end

  it 'mantém elegivel_em igual em todos os eventos, em retentativas e ao voltar a ficar elegível' do
    put_in_attendance
    travel 10.minutes
    at = Time.current
    stub_request(:post, url).with { |req| sent_bodies << JSON.parse(req.body) }
                            .to_return({ status: 503, body: 'fora do ar' }, { status: 201, body: hub_body.to_json })

    expect { service(at: at).perform }.to raise_error(Finture::HubClient::TransientError)
    expect(service(at: at).perform).to eq(:created)
    # A retentativa sai byte a byte igual (mesma sequência): o HUB deduplica.
    expect(sent_bodies[0]).to eq(sent_bodies[1])

    conversation.update!(custom_attributes: conversation.reload.custom_attributes.merge('sdr_stage' => 'em_triagem'))
    travel 1.hour
    conversation.update!(custom_attributes: conversation.reload.custom_attributes.merge('sdr_stage' => 'em_atendimento'))
    change_plan('Retomar contato')
    service.perform

    expect(sent_bodies.pluck('elegivel_em').uniq).to eq(['2026-11-12T14:00:00Z'])
    expect(sent_bodies.pluck('sequencia')).to eq([1, 1, 2])
  end

  it 'duas mudanças no mesmo segundo saem com sequências diferentes e crescentes' do
    put_in_attendance
    at = Time.current
    service(at: at).perform
    change_plan('Enviar proposta')
    service(at: at).perform

    expect(sent_bodies.pluck('ocorrido_em').uniq.size).to eq(1)
    expect(sent_bodies.pluck('sequencia')).to eq([1, 2])
    expect(sync.sequencia).to eq(2)
  end

  it 'evento rejeitado como futuro não fica synced e fica consultável mesmo sem demanda no HUB' do
    put_in_attendance
    stub_hub(hub_body(demanda: nil, motivo: 'futuro', ignorado: true), hub_body)

    expect(service.perform).to eq(:divergent)

    expect(sync).to have_attributes(status: 'divergent', hub_motivo: 'futuro', recovery_state: 'pending', hub_demanda_id: nil,
                                    last_payload_hash: nil, rejected_at: t0, recovered_at: nil)
    expect(Finture::DemandaSync.awaiting_recovery.where(hub_motivo: 'futuro').pluck(:conversation_id)).to eq([conversation.id])

    # O conteúdo igual NÃO é barrado: o próximo envio sai (de novo como created) e encerra a recuperação.
    travel 1.minute
    expect(service.perform).to eq(:created)
    expect(sync).to have_attributes(status: 'synced', recovery_state: 'recovered', recovered_at: t0 + 1.minute, hub_demanda_id: 'hub-1')
    expect(sent_bodies.pluck('evento', 'sequencia')).to eq([['created', 1], ['created', 2]])
  end

  it 'evento atrasado também fica divergent; duplicado conta como aplicado' do
    put_in_attendance
    stub_hub(hub_body(motivo: 'atrasado', ignorado: true), hub_body(motivo: 'duplicado'))

    expect(service.perform).to eq(:divergent)
    expect(sync).to have_attributes(status: 'divergent', hub_motivo: 'atrasado', hub_demanda_id: 'hub-1')

    expect(service.perform).to eq(:updated)
    expect(sync).to have_attributes(status: 'synced', hub_motivo: 'duplicado', recovery_state: 'recovered')
    expect(sync.last_payload_hash).to be_present
  end

  it 'não cria sem responsável nem fora de Em atendimento' do
    conversation.update!(custom_attributes: { 'sdr_stage' => 'em_atendimento' })
    expect(service.perform).to eq(:skipped)

    conversation.update!(assignee: agent, custom_attributes: { 'sdr_stage' => 'em_triagem' })
    expect(service.perform).to eq(:skipped)

    expect(WebMock).not_to have_requested(:post, url)
    expect(Finture::DemandaSync.count).to eq(0)
  end

  it 'não cria em caixa comercial nem com a integração desligada' do
    Finture::InboxConfig.find_by(inbox: inbox).update!(kanban_type: 'comercial')
    put_in_attendance
    expect(service.perform).to eq(:skipped)

    Finture::InboxConfig.find_by(inbox: inbox).update!(kanban_type: 'operacional')
    with_modified_env('FINTURE_HUB_INGEST_SECRET' => '') { expect(service.perform).to eq(:disabled) }

    expect(WebMock).not_to have_requested(:post, url)
  end

  it 'não reenvia o mesmo conteúdo, a não ser com force' do
    put_in_attendance
    service.perform

    expect(service.perform).to eq(:unchanged)
    expect(WebMock).to have_requested(:post, url).once

    expect(service(force: true).perform).to eq(:updated)
    expect(sent_bodies.pluck('sequencia')).to eq([1, 2])
  end

  it 'reenvia como updated quando o plano de ação, o responsável ou o status mudam' do
    put_in_attendance
    service.perform

    change_plan('Enviar proposta')
    expect(service.perform).to eq(:updated)
    expect(sent_bodies.last).to include('evento' => 'updated', 'plano_acao' => 'Enviar proposta')

    conversation.update!(assignee: nil, status: :resolved)
    expect(service.perform).to eq(:updated)
    expect(sent_bodies.last).to include('evento' => 'updated', 'responsavel_email' => nil, 'status_origem' => 'resolved')
    expect(sync).to have_attributes(last_event: 'updated', attempts: 3, sequencia: 3)
  end

  it 'erro passageiro do HUB deixa a linha em retrying e propaga para o job tentar de novo' do
    put_in_attendance
    stub_request(:post, url).to_return(status: 503, body: 'fora do ar')

    expect { service.perform }.to raise_error(Finture::HubClient::TransientError)
    expect(sync).to have_attributes(status: 'retrying', attempts: 1, sequencia: 1)
    expect(sync.last_error).to include('503')
  end

  it 'recusa do HUB (4xx) marca failed sem propagar e encerra a recuperação em aberto como failed' do
    put_in_attendance
    sync.update!(status: 'divergent', recovery_state: 'pending', hub_motivo: 'futuro')
    stub_request(:post, url).to_return(status: 401, body: '{"detail":{"code":"invalid_secret"}}')

    expect(service.perform).to eq(:failed)
    expect(sync).to have_attributes(status: 'failed', hub_demanda_id: nil, recovery_state: 'failed', attempts: 1)
    expect(sync.last_error).to include('401')
  end

  it 'usa o telefone no título quando o contato não tem nome' do
    conversation.contact.update!(name: '', phone_number: '+5500000000000')
    put_in_attendance('produto_interesse' => nil)
    service.perform

    expect(sent_bodies.last).to include('titulo' => '+5500000000000 — OPERACIONAL-Caixa Exemplo', 'produto_interesse' => nil)
  end

  describe 'compatibilidade com o v1' do
    # Fórmula do hash do v1 (PR anterior): corpo sem ocorrido_em/evento.
    def v1_digest(body)
      Digest::SHA256.hexdigest(body.to_h.reject { |key, _| %w[ocorrido_em evento].include?(key.to_s) }.to_json)
    end

    it 'FINTURE_HUB_PAYLOAD_VERSION=1 envia o payload v1 exato, que o HUB continua aceitando' do
      put_in_attendance
      with_modified_env('FINTURE_HUB_PAYLOAD_VERSION' => '1') { expect(service.perform).to eq(:created) }

      expect(sent_bodies.last['payload_version']).to eq(1)
      expect(sent_bodies.last.keys).not_to include('sequencia', 'elegivel_em', 'conversa_criada_em', 'autor')
      expect(sync).to have_attributes(status: 'synced', sequencia: 0)
    end

    it 'linha sincronizada pelo v1 não é reenviada só pela troca de versão (nem na volta ao v1)' do
      put_in_attendance
      v1_body = nil
      with_modified_env('FINTURE_HUB_PAYLOAD_VERSION' => '1') { v1_body = service.payload('updated') }
      sync.update!(status: 'synced', hub_demanda_id: 'hub-1', last_payload_hash: v1_digest(v1_body))

      expect(service.perform).to eq(:unchanged)
      with_modified_env('FINTURE_HUB_PAYLOAD_VERSION' => '1') { expect(service.perform).to eq(:unchanged) }
      expect(WebMock).not_to have_requested(:post, url)
    end
  end
end
