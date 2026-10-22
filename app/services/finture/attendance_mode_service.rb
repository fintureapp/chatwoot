# Única porta de troca do modo de atendimento (IA x humano) de uma conversa.
#
# Toda troca roda com a conversa travada (SELECT ... FOR UPDATE), confere a
# revisão esperada (duas ações simultâneas: uma vence, a outra recebe 409),
# incrementa a revisão, grava a trilha (Finture::AttendanceTransition) e espelha
# os sinais antigos — custom_attributes.modo_atendimento e a etiqueta
# atendimento_humano — numa única gravação da conversa, para o guard antigo do
# n8n, o SLA do Dashboard SDR e a lista/kanban (via conversation.updated)
# continuarem funcionando. A mesma trava é usada pelo Finture::BotMessageGuard
# no envio do bot: nenhuma mensagem do bot é criada depois de alguém assumir.
class Finture::AttendanceModeService
  MODE_KEY = Finture::AttendanceState::MODE_KEY
  HUMAN_LABEL = Finture::AttendanceState::HUMAN_LABEL

  pattr_initialize [:conversation!]

  # Atendente assume: modo humano + ele como responsável (abre se estava pendente).
  def take_over!(user:, reason: nil, expected_revision: nil)
    change!(expected_revision: expected_revision) do |state|
      next if state.human? && conversation.assignee_id == user.id

      conversation.assignee = user
      conversation.assignee_agent_bot = nil
      conversation.status = :open if conversation.pending?
      { to: 'humano', actor: user, source: 'dashboard_take_over', reason: reason, activity: [:take_over, { user_name: user.available_name }] }
    end
  end

  # Devolução explícita: só em caixa com IA, conversa aberta/pendente e em modo
  # humano. Tira o responsável (mantém o time) e guarda o contexto de retomada.
  def return_to_ai!(user:, reason:, pending_notes: nil, expected_revision: nil)
    reason = reason.to_s.strip
    raise error(:reason_required) if reason.blank?

    change!(expected_revision: expected_revision) do |state|
      ensure_returnable!(state)
      context = resume_context_for(state, user, reason, pending_notes)
      conversation.assignee = nil
      { to: 'ia', actor: user, source: 'dashboard_return', reason: reason, pending_notes: pending_notes,
        resume_context: context, activity: return_activity(user, reason, context['pending_notes']) }
    end
  end

  # Handoff do bot (triagem do n8n): humano, sem responsável (o n8n atribui o
  # time). A revisão nova devolvida libera a mensagem de confirmação do bot.
  def bot_handoff!(reason: nil, triage: nil, expected_revision: nil)
    change!(expected_revision: expected_revision) do |state|
      next if state.human?

      { to: 'humano', actor: :bot, source: 'n8n_handoff', reason: reason,
        resume_context: { 'triage' => triage.presence }.compact, activity: [:bot_handoff, { reason: reason.presence || '-' }] }
    end
  end

  # Caminhos antigos que já significavam "humano" (etiqueta manual, atribuição a
  # agente, POST legado em custom_attributes, conversa aberta por agente).
  # Só escala: nunca devolve à IA. `occurred_before` descarta evento atrasado
  # (listener assíncrono) quando o modo já mudou depois dele.
  def escalate!(source:, user: nil, occurred_before: nil)
    change! do |state|
      next if state.human? || stale_event?(state, occurred_before)

      { to: 'humano', actor: user || :system, source: source, activity: escalation_activity(source, user) }
    end
  end

  # Cliente reabriu uma conversa resolvida: em caixa com IA, a triagem recomeça.
  def reopen_to_ai!
    return unless Finture::InboxConfig.ai_enabled?(conversation.inbox_id)

    change! do |state|
      next if state.ia?

      conversation.assignee = nil
      { to: 'ia', actor: :system, source: 'reopen_by_contact', resume_context: {}, activity: [:reopened, {}] }
    end
  end

  private

  # Trava a conversa, monta a troca no bloco (nil = nada a fazer) e aplica tudo
  # numa transação. Devolve o estado (persistido ou derivado) após a operação.
  def change!(expected_revision: nil)
    activity = nil
    state = nil
    # reload(lock: true) em vez de with_lock: conversa recém-criada carrega o
    # display_id do trigger como "mudança" e o with_lock recusa travar.
    Conversation.transaction do
      conversation.reload(lock: true)
      state = Finture::AttendanceState.for(conversation)
      raise conflict(state) if expected_revision.present? && expected_revision.to_i != state.revision

      plan = yield(state)
      next if plan.nil?

      activity = plan[:activity]
      apply!(state, plan)
    end
    post_activity(activity) if activity
    state
  end

  def apply!(state, plan)
    from = state.persisted? ? state.mode : nil
    actor_type, user = actor_of(plan[:actor])
    update_state!(state, plan, actor_type, user)
    record_transition!(state, plan, from, actor_type, user)
    mirror!(plan[:to])
  end

  def update_state!(state, plan, actor_type, user)
    state.assign_attributes(
      mode: plan[:to], revision: state.revision + 1, source: plan[:source], changed_at: Time.current,
      changed_by_type: actor_type, changed_by_id: user&.id, changed_by_name: user&.available_name || actor_label(actor_type)
    )
    state.resume_context = plan[:resume_context] if plan.key?(:resume_context)
    state.save!
    # Estado recém-criado: atualiza o cache da associação para o broadcast
    # (push_data) sair com a revisão nova, não com o estado derivado.
    conversation.association(:finture_attendance_state).target = state
  end

  def record_transition!(state, plan, from, actor_type, user)
    Finture::AttendanceTransition.create!(
      account_id: conversation.account_id, conversation_id: conversation.id, inbox_id: conversation.inbox_id,
      user_id: user&.id, actor_type: actor_type, from_mode: from, to_mode: plan[:to], source: plan[:source],
      reason: plan[:reason].to_s.strip.presence&.truncate(255), pending_notes: plan[:pending_notes].to_s.strip.presence,
      revision: state.revision, occurred_at: state.changed_at
    )
  end

  # Espelho dos sinais antigos + mudanças montadas no bloco, numa gravação só
  # (um único conversation.updated). Se nada mudou na conversa, avisa mesmo
  # assim para lista/kanban receberem o estado novo.
  def mirror!(mode)
    attrs = (conversation.custom_attributes || {}).dup
    attrs[MODE_KEY] = mode
    conversation.custom_attributes = attrs

    labels = conversation.label_list.to_a
    conversation.label_list = mode == 'humano' ? (labels | [HUMAN_LABEL]) : (labels - [HUMAN_LABEL])

    if conversation.changed?
      conversation.save!
    else
      conversation.dispatch_conversation_updated_event
    end
  end

  def resume_context_for(state, user, reason, pending_notes)
    {
      'reason' => reason, 'pending_notes' => pending_notes.to_s.strip.presence,
      'returned_by' => user.available_name, 'returned_at' => Time.current.iso8601,
      'last_assignee_id' => conversation.assignee_id, 'last_assignee_name' => conversation.assignee&.available_name,
      'triage' => state.resume_context['triage']
    }.compact
  end

  def ensure_returnable!(state)
    raise error(:ai_disabled) unless Finture::InboxConfig.ai_enabled?(conversation.inbox_id)
    raise error(:not_open) unless conversation.open? || conversation.pending?
    raise error(:already_ai) if state.ia?
  end

  def stale_event?(state, occurred_before)
    occurred_before.present? && state.changed_at.present? && state.changed_at > occurred_before
  end

  def return_activity(user, reason, notes)
    args = { user_name: user.available_name, reason: reason }
    notes.present? ? [:return_to_ai_with_notes, args.merge(notes: notes)] : [:return_to_ai, args]
  end

  # Conversa criada pelo agente já nasce humana: não polui a linha do tempo.
  def escalation_activity(source, user)
    return if source == 'agent_created'

    [:escalated, { user_name: user&.available_name || actor_label(:system) }]
  end

  def actor_of(actor)
    return ['user', actor] if actor.is_a?(User)

    [actor.to_s, nil]
  end

  def actor_label(actor_type)
    I18n.t("finture.attendance.actors.#{actor_type}", default: actor_type.to_s)
  end

  def conflict(state)
    CustomExceptions::Finture::AttendanceConflict.new(state: state, conversation: conversation)
  end

  def error(key)
    CustomExceptions::Finture::AttendanceNotAllowed.new(key: key)
  end

  def post_activity((key, args))
    content = I18n.t("finture.attendance.activity.#{key}", **args)
    Conversations::ActivityMessageJob.perform_later(
      conversation,
      { account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
    )
  end
end
