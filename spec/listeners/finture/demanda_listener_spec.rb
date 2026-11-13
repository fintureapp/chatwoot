require 'rails_helper'

RSpec.describe Finture::DemandaListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:env) { { 'FINTURE_HUB_BASE_URL' => 'https://hub.test', 'FINTURE_HUB_INGEST_SECRET' => 'segredo' } }

  around { |example| with_modified_env(env) { example.run } }

  before { Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional') }

  def event(changes)
    Events::Base.new('conversation.updated', Time.zone.now, conversation: conversation, changed_attributes: changes)
  end

  def expect_enqueued(changes)
    expect { listener.conversation_updated(event(changes)) }.to have_enqueued_job(Finture::DemandaSyncJob).with(conversation.id, anything)
  end

  def expect_not_enqueued(changes)
    expect { listener.conversation_updated(event(changes)) }.not_to have_enqueued_job(Finture::DemandaSyncJob)
  end

  it 'enfileira para responsável, status e time' do
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

  it 'é disparado pelo despachante quando a conversa muda de responsável' do
    perform_enqueued_jobs(only: EventDispatcherJob) { conversation.update!(assignee: agent) }

    expect(Finture::DemandaSyncJob).to have_been_enqueued.with(conversation.id, anything)
  end
end
