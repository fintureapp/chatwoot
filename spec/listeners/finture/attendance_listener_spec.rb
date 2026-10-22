require 'rails_helper'

RSpec.describe Finture::AttendanceListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def event(changes, timestamp: Time.zone.now)
    Events::Base.new('conversation.updated', timestamp, conversation: conversation, changed_attributes: changes)
  end

  def mode
    Finture::AttendanceState.for(conversation.reload).mode
  end

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'etiqueta atendimento_humano aplicada à mão passa para humano' do
    conversation.update!(label_list: ['atendimento_humano'])
    listener.conversation_updated(event({ 'label_list' => [[], ['atendimento_humano']] }))

    expect(mode).to eq('humano')
  end

  it 'etiqueta aplicada numa conversa já devolvida à IA volta a pausar a IA' do
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'comercial', ai_enabled: true)
    service = Finture::AttendanceModeService.new(conversation: conversation)
    service.take_over!(user: agent)
    service.return_to_ai!(user: agent, reason: 'x')
    conversation.update!(label_list: ['atendimento_humano'])

    listener.conversation_updated(event({ 'label_list' => [[], ['atendimento_humano']] }))
    expect(Finture::AttendanceState.for(conversation.reload)).to have_attributes(mode: 'humano', source: 'label')
  end

  it 'atribuição a um agente passa para humano' do
    conversation.update!(assignee: agent)
    listener.conversation_updated(event({ 'assignee_id' => [nil, agent.id] }))

    expect(Finture::AttendanceState.for(conversation.reload)).to have_attributes(mode: 'humano', source: 'assignment')
  end

  it 'ignora o evento se a etiqueta já saiu (evento atrasado)' do
    listener.conversation_updated(event({ 'label_list' => [[], ['atendimento_humano']] }))
    expect(mode).to eq('ia')
  end

  it 'remover etiqueta ou responsável não devolve à IA' do
    Finture::AttendanceModeService.new(conversation: conversation).take_over!(user: agent)
    conversation.update!(assignee: nil, label_list: [])

    listener.conversation_updated(event({ 'assignee_id' => [agent.id, nil], 'label_list' => [['atendimento_humano'], []] }))
    expect(mode).to eq('humano')
  end
end
