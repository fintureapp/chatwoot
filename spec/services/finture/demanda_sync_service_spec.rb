require 'rails_helper'

RSpec.describe Finture::DemandaSyncService do
  let(:account) { create(:account) }
  # Sem atribuição automática: a elegibilidade depende de QUEM atribui o responsável.
  let(:inbox) { create(:inbox, account: account, name: 'OPERACIONAL-Finture Parceiros', enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent, name: 'Thiago Zeny', email: 'Thiago.Zeny@criteriafg.com.br') }
  let(:team) { create(:team, account: account, name: 'Atendimento Parceiros') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { 'https://hub.test/api/v1/demandas/ingest' }
  let(:env) do
    { 'FINTURE_HUB_BASE_URL' => 'https://hub.test', 'FINTURE_HUB_INGEST_SECRET' => 'segredo',
      'FRONTEND_URL' => 'https://chat.finture.app' }
  end

  let(:sent_bodies) { [] }

  around { |example| with_modified_env(env) { example.run } }

  before do
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional')
    # O responsável precisa ser membro da caixa e do time, senão o AssignmentHandler o remove.
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    stub_request(:post, url).with { |req| sent_bodies << JSON.parse(req.body) }
                            .to_return(status: 201, body: { demanda: { id: 'hub-1' }, criada: true }.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
  end

  def service(conv = conversation.reload)
    described_class.new(conversation: conv, occurred_at: Time.zone.parse('2026-11-12T14:03:22Z'))
  end

  def put_in_attendance(extra = {})
    conversation.update!(assignee: agent, team: team,
                         custom_attributes: { 'sdr_stage' => 'em_atendimento', 'sdr_next_action' => 'Ligar para o Gean',
                                              'sdr_resumo_ia' => 'Cliente quer portfólio.', 'produto_interesse' => 'Consórcio' }.merge(extra))
  end

  it 'cria a demanda quando a conversa está em Em atendimento com responsável' do
    put_in_attendance

    expect(service.perform).to eq(:created)

    sync = conversation.reload.finture_demanda_sync
    expect(sync).to have_attributes(status: 'synced', hub_demanda_id: 'hub-1', last_event: 'created', attempts: 1,
                                    external_id: "chatwoot:#{account.id}:#{conversation.display_id}")
    body = sent_bodies.last
    expect(body).to include(
      'origem' => 'chatwoot', 'evento' => 'created', 'payload_version' => 1,
      'external_id' => "chatwoot:#{account.id}:#{conversation.display_id}",
      'titulo' => "#{conversation.contact.name} — Consórcio",
      'contexto' => 'Cliente quer portfólio.', 'plano_acao' => 'Ligar para o Gean', 'resumo_final' => nil,
      'responsavel_email' => 'thiago.zeny@criteriafg.com.br', 'responsavel_nome' => 'Thiago Zeny',
      'time' => 'atendimento parceiros', 'canal' => 'WebWidget', 'etapa' => 'em_atendimento', 'status_origem' => 'open',
      'produto_interesse' => 'Consórcio', 'ocorrido_em' => '2026-11-12T14:03:22Z',
      'link' => "https://chat.finture.app/app/accounts/#{account.id}/conversations/#{conversation.display_id}"
    )
    expect(body['caixa']).to eq('id' => inbox.id, 'nome' => 'OPERACIONAL-Finture Parceiros')
    expect(body['contato']).to include('nome' => conversation.contact.name, 'email' => conversation.contact.email)
    expect(WebMock).to have_requested(:post, url).with(headers: { 'X-Ingest-Secret' => 'segredo' }).once
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
    put_in_attendance
    Finture::InboxConfig.find_by(inbox: inbox).update!(kanban_type: 'comercial')
    expect(service.perform).to eq(:skipped)

    Finture::InboxConfig.find_by(inbox: inbox).update!(kanban_type: 'operacional')
    with_modified_env('FINTURE_HUB_INGEST_SECRET' => '') { expect(service.perform).to eq(:disabled) }

    expect(WebMock).not_to have_requested(:post, url)
  end

  it 'não reenvia o mesmo payload duas vezes' do
    put_in_attendance
    service.perform

    expect(service.perform).to eq(:unchanged)
    expect(WebMock).to have_requested(:post, url).once
  end

  it 'reenvia como updated quando o plano de ação, o responsável ou o status mudam' do
    put_in_attendance
    service.perform

    conversation.update!(custom_attributes: conversation.custom_attributes.merge('sdr_next_action' => 'Enviar proposta'))
    expect(service.perform).to eq(:updated)
    expect(sent_bodies.last).to include('evento' => 'updated', 'plano_acao' => 'Enviar proposta')

    conversation.update!(assignee: nil, status: :resolved)
    expect(service.perform).to eq(:updated)
    expect(sent_bodies.last).to include('evento' => 'updated', 'responsavel_email' => nil, 'status_origem' => 'resolved')
    expect(conversation.reload.finture_demanda_sync).to have_attributes(last_event: 'updated', attempts: 3)
  end

  it 'erro passageiro do HUB deixa a linha em retrying e propaga para o job tentar de novo' do
    put_in_attendance
    stub_request(:post, url).to_return(status: 503, body: 'fora do ar')

    expect { service.perform }.to raise_error(Finture::HubClient::TransientError)
    expect(conversation.reload.finture_demanda_sync).to have_attributes(status: 'retrying', attempts: 1)
    expect(conversation.finture_demanda_sync.last_error).to include('503')
  end

  it 'recusa do HUB (4xx) marca failed sem propagar' do
    put_in_attendance
    stub_request(:post, url).to_return(status: 401, body: '{"detail":{"code":"invalid_secret"}}')

    expect(service.perform).to eq(:failed)
    expect(conversation.reload.finture_demanda_sync).to have_attributes(status: 'failed', hub_demanda_id: nil)
    expect(conversation.finture_demanda_sync.last_error).to include('401')
  end

  it 'usa o telefone no título quando o contato não tem nome' do
    conversation.contact.update!(name: '', phone_number: '+5521999990000')
    put_in_attendance('produto_interesse' => nil)
    service.perform

    expect(sent_bodies.last).to include('titulo' => '+5521999990000 — OPERACIONAL-Finture Parceiros', 'produto_interesse' => nil)
  end
end
