require 'rails_helper'

RSpec.describe Finture::DemandaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:env) { { 'FINTURE_HUB_BASE_URL' => 'https://hub.example.test', 'FINTURE_HUB_INGEST_SECRET' => 'segredo-de-teste' } }
  let(:at) { Time.zone.parse('2026-11-12T14:00:00Z') }

  around do |example|
    with_modified_env(env) { example.run }
  ensure
    Current.reset
  end

  before do
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional')
    create(:inbox_member, inbox: inbox, user: agent)
  end

  def event(changes)
    Events::Base.new('conversation.updated', at, conversation: conversation, changed_attributes: changes)
  end

  # Sem autor, o job sai com os 2 argumentos do v1.
  def expect_enqueued(changes, actor_id = nil)
    arguments = [conversation.id, at.iso8601]
    arguments << actor_id if actor_id
    expect { listener.conversation_updated(event(changes)) }
      .to have_enqueued_job(Finture::DemandaSyncJob).with(*arguments)
  end

  def expect_not_enqueued(changes)
    expect { listener.conversation_updated(event(changes)) }.not_to have_enqueued_job(Finture::DemandaSyncJob)
  end

  # Grava sem passar pelo despachante, para o teste controlar o evento.
  def set_state(stage:, assignee:)
    conversation.update_columns(custom_attributes: { 'sdr_stage' => stage }, assignee_id: assignee&.id) # rubocop:disable Rails/SkipsModelValidations
    conversation.reload
  end

  it 'enfileira para responsável, status e time, com o horário do evento' do
    expect_enqueued({ 'assignee_id' => [nil, agent.id] })
    expect_enqueued({ 'status' => %w[open resolved] })
    expect_enqueued({ 'team_id' => [nil, 7] })
  end

  it 'enfileira quando uma chave vigiada de custom_attributes muda' do
    expect_enqueued({ 'custom_attributes' => [{ 'sdr_stage' => 'em_triagem' }, { 'sdr_stage' => 'em_atendimento' }] })
    expect_enqueued({ 'custom_attributes' => [{}, { 'sdr_next_action' => 'Ligar' }] })
    expect_enqueued({ 'custom_attributes' => [{ 'sdr_resumo_ia' => nil }, { 'sdr_resumo_ia' => 'Resumo' }] })
    expect_enqueued({ 'custom_attributes' => [{}, { 'sdr_resumo' => 'Final' }] })
    expect_enqueued({ 'custom_attributes' => [{}, { 'produto_interesse' => 'Saúde' }] })
  end

  it 'ignora etiqueta, prioridade e custom_attributes sem mudança vigiada' do
    expect_not_enqueued({ 'label_list' => [[], ['atendimento_humano']] })
    expect_not_enqueued({ 'priority' => [nil, 'high'] })
    expect_not_enqueued({ 'snoozed_until' => [nil, 1.day.from_now] })
    expect_not_enqueued({ 'custom_attributes' => [{ 'sdr_stage' => 'em_atendimento', 'modo_atendimento' => 'ia' },
                                                  { 'sdr_stage' => 'em_atendimento', 'modo_atendimento' => 'humano' }] })
    expect_not_enqueued({})
  end

  it 'ignora caixa comercial e integração desligada' do
    Finture::InboxConfig.find_by(inbox: inbox).update!(kanban_type: 'comercial')
    expect_not_enqueued({ 'assignee_id' => [nil, agent.id] })

    Finture::InboxConfig.find_by(inbox: inbox).update!(kanban_type: 'operacional')
    with_modified_env('FINTURE_HUB_BASE_URL' => '') { expect_not_enqueued({ 'assignee_id' => [nil, agent.id] }) }
  end

  it 'não propaga erro, para não barrar os listeners seguintes' do
    allow(Finture::InboxConfig).to receive(:operational?).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect { listener.conversation_updated(event({ 'assignee_id' => [nil, agent.id] })) }.not_to raise_error
  end

  describe 'autor' do
    it 'passa o usuário do painel que fez a mudança' do
      Current.user = agent
      expect_enqueued({ 'status' => %w[open resolved] }, agent.id)
    end

    it 'não passa autor para automação, token de API, bot ou sistema' do
      Current.user = agent
      Current.executed_by = create(:automation_rule, account: account)
      expect_enqueued({ 'status' => %w[open resolved] }, nil)

      Current.executed_by = nil
      Current.api_access_token_auth = true
      expect_enqueued({ 'status' => %w[open resolved] }, nil)

      Current.reset
      Current.user = create(:agent_bot)
      expect_enqueued({ 'status' => %w[open resolved] }, nil)

      Current.reset
      expect_enqueued({ 'status' => %w[open resolved] }, nil)
    end
  end

  describe 'elegivel_em' do
    it 'cria a linha com o horário do evento quando a conversa acaba de ficar elegível' do
      set_state(stage: 'em_atendimento', assignee: agent)

      listener.conversation_updated(event({ 'assignee_id' => [nil, agent.id] }))

      expect(conversation.reload.finture_demanda_sync).to have_attributes(elegivel_em: at, status: 'pending')
    end

    it 'vale também quando a etapa é a última condição a ser cumprida' do
      set_state(stage: 'em_atendimento', assignee: agent)

      listener.conversation_updated(event({ 'custom_attributes' => [{ 'sdr_stage' => 'em_triagem' }, { 'sdr_stage' => 'em_atendimento' }] }))

      expect(conversation.reload.finture_demanda_sync.elegivel_em).to eq(at)
    end

    it 'não registra quando a conversa já era elegível antes da mudança (instante desconhecido)' do
      set_state(stage: 'em_atendimento', assignee: agent)

      listener.conversation_updated(event({ 'team_id' => [nil, 7] }))

      expect(conversation.reload.finture_demanda_sync).to be_nil
    end

    it 'nunca sobrescreve o elegivel_em já registrado' do
      set_state(stage: 'em_atendimento', assignee: agent)
      listener.conversation_updated(event({ 'assignee_id' => [nil, agent.id] }))

      later = Events::Base.new('conversation.updated', at + 2.hours, conversation: conversation,
                                                                     changed_attributes: { 'assignee_id' => [nil, agent.id] })
      listener.conversation_updated(later)

      expect(conversation.reload.finture_demanda_sync.elegivel_em).to eq(at)
    end

    it 'não registra enquanto a conversa não está elegível' do
      set_state(stage: 'em_triagem', assignee: agent)

      listener.conversation_updated(event({ 'assignee_id' => [nil, agent.id] }))

      expect(Finture::DemandaSync.count).to eq(0)
    end
  end

  it 'é disparado pelo despachante (síncrono), com o autor da requisição' do
    Current.user = agent
    conversation.update!(assignee: agent, custom_attributes: { 'sdr_stage' => 'em_atendimento' })

    expect(Finture::DemandaSyncJob).to have_been_enqueued.with(conversation.id, anything, agent.id)
    expect(conversation.reload.finture_demanda_sync.elegivel_em).to be_present
  end
end
