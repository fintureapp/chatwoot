require 'rails_helper'

RSpec.describe Finture::AttendanceModeService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team) }
  let(:service) { described_class.new(conversation: conversation) }

  def state
    Finture::AttendanceState.for(conversation.reload)
  end

  def enable_ai!
    Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'comercial', ai_enabled: true)
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: other_agent)
  end

  describe 'estado derivado (sem linha gravada)' do
    it 'é IA por padrão' do
      expect(state).to have_attributes(mode: 'ia', revision: 0)
    end

    it 'segue a regra antiga do guard: atributo humano ou etiqueta sem atributo' do
      conversation.update!(label_list: ['atendimento_humano'])
      expect(state.mode).to eq('humano')

      conversation.update!(custom_attributes: { 'modo_atendimento' => 'ia' })
      expect(state.mode).to eq('ia')
    end
  end

  describe '#take_over!' do
    it 'passa para humano, atribui, espelha os sinais e registra a transição' do
      service.take_over!(user: agent, reason: 'cliente pediu')

      conversation.reload
      expect(state).to have_attributes(mode: 'humano', revision: 1, source: 'dashboard_take_over', changed_by_name: agent.available_name)
      expect(conversation.assignee).to eq(agent)
      expect(conversation.custom_attributes['modo_atendimento']).to eq('humano')
      expect(conversation.label_list).to include('atendimento_humano')

      transition = Finture::AttendanceTransition.last
      expect(transition).to have_attributes(from_mode: nil, to_mode: 'humano', actor_type: 'user', user_id: agent.id,
                                            reason: 'cliente pediu', revision: 1)
    end

    it 'abre a conversa pendente' do
      conversation.update!(status: :pending)
      service.take_over!(user: agent)
      expect(conversation.reload).to be_open
    end

    it 'é idempotente para quem já está com a conversa' do
      service.take_over!(user: agent)
      expect { service.take_over!(user: agent) }.not_to change(Finture::AttendanceTransition, :count)
      expect(state.revision).to eq(1)
    end

    it 'recusa com conflito quando a revisão lida ficou velha (dois cliques ao mesmo tempo)' do
      described_class.new(conversation: conversation).take_over!(user: agent, expected_revision: 0)

      expect do
        described_class.new(conversation: Conversation.find(conversation.id)).take_over!(user: other_agent, expected_revision: 0)
      end.to raise_error(CustomExceptions::Finture::AttendanceConflict, /#{agent.available_name}/)
      expect(conversation.reload.assignee).to eq(agent)
    end

    it 'expõe o estado novo no payload do ActionCable/webhook' do
      service.take_over!(user: agent)
      expect(conversation.push_event_data[:finture_attendance]).to include(mode: 'humano', revision: 1)
    end

    it 'registra a atividade na conversa' do
      expect { service.take_over!(user: agent) }.to have_enqueued_job(Conversations::ActivityMessageJob)
    end
  end

  describe '#return_to_ai!' do
    before do
      enable_ai!
      service.take_over!(user: agent)
    end

    it 'volta para IA, tira o responsável, mantém o time e guarda o contexto' do
      service.return_to_ai!(user: other_agent, reason: 'dúvida simples', pending_notes: 'enviar boleto')

      conversation.reload
      expect(state).to have_attributes(mode: 'ia', revision: 2, source: 'dashboard_return')
      expect(conversation.assignee).to be_nil
      expect(conversation.team).to eq(team)
      expect(conversation.label_list).not_to include('atendimento_humano')
      expect(conversation.custom_attributes['modo_atendimento']).to eq('ia')
      expect(state.resume_context).to include('reason' => 'dúvida simples', 'pending_notes' => 'enviar boleto',
                                              'last_assignee_id' => agent.id)
    end

    it 'exige motivo' do
      expect { service.return_to_ai!(user: agent, reason: ' ') }
        .to raise_error(CustomExceptions::Finture::AttendanceNotAllowed)
    end

    it 'não devolve em caixa sem IA' do
      Finture::InboxConfig.find_by(inbox: inbox).update!(ai_enabled: false)
      expect { service.return_to_ai!(user: agent, reason: 'x') }
        .to raise_error(CustomExceptions::Finture::AttendanceNotAllowed)
    end

    it 'não devolve conversa resolvida' do
      conversation.update!(status: :resolved)
      expect { service.return_to_ai!(user: agent, reason: 'x') }
        .to raise_error(CustomExceptions::Finture::AttendanceNotAllowed)
    end

    it 'não devolve o que já está com a IA' do
      service.return_to_ai!(user: agent, reason: 'x')
      expect { service.return_to_ai!(user: agent, reason: 'x') }
        .to raise_error(CustomExceptions::Finture::AttendanceNotAllowed)
    end
  end

  describe '#bot_handoff!' do
    it 'passa para humano com ator bot e guarda a triagem' do
      service.bot_handoff!(reason: 'Triagem', triage: { 'tipo' => 'indicacao', 'produto' => 'saude' })

      expect(state).to have_attributes(mode: 'humano', changed_by_type: 'bot', source: 'n8n_handoff')
      expect(state.resume_context['triage']).to include('produto' => 'saude')
      expect(conversation.reload.assignee).to be_nil
    end

    it 'não faz nada se um humano já assumiu' do
      service.take_over!(user: agent)
      service.bot_handoff!(reason: 'Triagem')
      expect(state).to have_attributes(changed_by_type: 'user', revision: 1)
    end
  end

  describe '#escalate!' do
    it 'só escala, nunca devolve' do
      service.escalate!(source: 'label')
      expect(state.mode).to eq('humano')
      expect { service.escalate!(source: 'label') }.not_to change(Finture::AttendanceTransition, :count)
    end

    it 'ignora evento atrasado quando o modo mudou depois dele' do
      enable_ai!
      service.take_over!(user: agent)
      service.return_to_ai!(user: agent, reason: 'x')

      service.escalate!(source: 'assignment', occurred_before: 1.minute.ago)
      expect(state.mode).to eq('ia')
    end
  end

  describe '#reopen_to_ai!' do
    it 'em caixa com IA, volta para a IA sem responsável' do
      enable_ai!
      service.take_over!(user: agent)
      service.reopen_to_ai!

      expect(state).to have_attributes(mode: 'ia', source: 'reopen_by_contact', resume_context: {})
      expect(conversation.reload.assignee).to be_nil
    end

    it 'em caixa sem IA, não muda nada' do
      service.take_over!(user: agent)
      service.reopen_to_ai!
      expect(state.mode).to eq('humano')
    end
  end
end
