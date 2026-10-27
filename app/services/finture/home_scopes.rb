# Escopos da Home (Finture::HomeOverviewService): os filtros e a
# definição de CADA indicador num lugar só. O resumo conta `metric(nome)` e a
# lista do indicador lê o mesmo `metric(nome)` — por isso os totais batem.
class Finture::HomeScopes
  include Finture::SdrShared

  OPEN_STATUSES = %i[open pending].freeze
  NO_TEAM = 'none'.freeze

  # Modo de atendimento em SQL — mesma regra de Finture::AttendanceState.derive_mode:
  # estado persistido; sem ele, custom_attributes.modo_atendimento; sem ele, a
  # label atendimento_humano.
  MODE_SQL = <<~'SQL'.squish.freeze
    COALESCE(finture_attendance_states.mode,
      CASE LOWER(TRIM(conversations.custom_attributes ->> 'modo_atendimento'))
        WHEN 'humano' THEN 'humano'
        WHEN 'ia' THEN 'ia'
        ELSE CASE WHEN COALESCE(conversations.cached_label_list, '') ~ '(^|,)\s*atendimento_humano\s*(,|$)'
                  THEN 'humano' ELSE 'ia' END
      END)
  SQL

  # Volume do lead (custom_attributes.valor_potencial). Só conta o que é número
  # — mesma leitura do Kanban (Number(...)); texto livre vira "sem valor".
  VALUE_SQL = <<~'SQL'.squish.freeze
    CASE WHEN TRIM(conversations.custom_attributes ->> 'valor_potencial') ~ '^-?[0-9]+(\.[0-9]+)?$'
         THEN TRIM(conversations.custom_attributes ->> 'valor_potencial')::numeric END
  SQL
  OUTCOME_AT_SQL = "(conversations.custom_attributes ->> 'sdr_outcome_at')::bigint".freeze

  # indicador => método que devolve o escopo de conversas.
  CONVERSATION_METRICS = {
    'entered' => :entered_scope,
    'resolved' => :resolved_scope,
    'won' => :won_scope,
    'lost' => :lost_scope,
    'pipeline_open' => :pipeline_open_scope,
    'with_ai' => :ai_scope,
    'attending' => :attending_scope,
    'unassigned' => :unassigned_scope,
    'waiting_reply' => :waiting_scope
  }.freeze
  METRICS = CONVERSATION_METRICS.keys.freeze

  pattr_initialize [:account!, :current_user!, :inbox_id, :team_id, :purpose, :range!, :now!]

  def metric(name)
    public_send(CONVERSATION_METRICS.fetch(name))
  end

  # ---- Escopo base ----------------------------------------------------------
  # A conta inteira para QUALQUER usuário (decisão de produto, 27/10/2026): a
  # Home é o painel comum da operação, então não usa visible_conversations
  # (Finture::SdrShared), que recortaria o agente às caixas de que é membro.
  def conversations_scope
    @conversations_scope ||= begin
      scope = account.conversations
      scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
      scope = scope.where(team_id: team_id == NO_TEAM ? nil : team_id) if team_id.present?
      purpose_filter(scope)
    end
  end

  def operational_inbox_ids
    @operational_inbox_ids ||= Finture::InboxConfig.where(account_id: account.id, kanban_type: 'operacional').pluck(:inbox_id)
  end

  def ai_inbox_ids
    @ai_inbox_ids ||= Finture::InboxConfig.where(account_id: account.id, ai_enabled: true).pluck(:inbox_id)
  end

  # ---- Estoque: o que está em aberto agora ----------------------------------
  def open_scope
    conversations_scope.where(status: OPEN_STATUSES)
  end

  # Em aberto conduzidas pela IA. Só existe em caixa com IA ligada: nas demais
  # toda conversa é do time humano.
  def ai_scope
    return open_scope.none if ai_inbox_ids.empty?

    open_scope.where(inbox_id: ai_inbox_ids).left_joins(:finture_attendance_state).where("#{MODE_SQL} = 'ia'")
  end

  def human_scope
    open_scope.where.not(id: ai_scope.select(:id))
  end

  # "Em atendimento" do wallboard: status open com responsável.
  def attending_scope
    conversations_scope.where(status: :open).where.not(assignee_id: nil)
  end

  def unassigned_scope
    human_scope.where(assignee_id: nil)
  end

  # waiting_since: o cliente escreveu e ninguém respondeu ainda (nativo do Chatwoot).
  def waiting_scope
    human_scope.where.not(waiting_since: nil)
  end

  # Funil comercial ativo: o mesmo board do Kanban — lead sem desfecho, em
  # qualquer data de entrada.
  def pipeline_open_scope
    commercial_scope.where("conversations.custom_attributes ->> 'sdr_outcome' IS NULL")
  end

  # ---- Eventos do período ---------------------------------------------------
  def entered_scope
    conversations_scope.where(created_at: range)
  end

  def resolved_scope
    conversations_scope.where(id: resolution_events.select(:conversation_id))
  end

  # Última resolução no período de cada conversa de resolved_scope (série do gráfico).
  def resolution_times
    resolution_events.where(conversation_id: conversations_scope.select(:id)).group(:conversation_id).maximum(:created_at).values
  end

  # Ganho/perdido pela data do desfecho (sdr_outcome_at, gravado pelo
  # Finture::OutcomeService), não pela data de entrada do lead.
  def won_scope
    outcome_in_range('won')
  end

  def lost_scope
    outcome_in_range('lost')
  end

  # Soma de valor_potencial e quantos leads não têm valor numérico.
  def volume(scope)
    total, missing = scope.pick(Arel.sql("COALESCE(SUM(#{VALUE_SQL}), 0)"), Arel.sql("COUNT(*) FILTER (WHERE #{VALUE_SQL} IS NULL)"))
    { value: total.to_f, without_value: missing.to_i }
  end

  private

  def resolution_events
    ReportingEvent.where(account_id: account.id, name: 'conversation_resolved', created_at: range)
  end

  def commercial_scope
    conversations_scope.where.not(inbox_id: operational_inbox_ids)
  end

  def outcome_in_range(outcome)
    commercial_scope.where("conversations.custom_attributes ->> 'sdr_outcome' = ?", outcome)
                    .where("#{OUTCOME_AT_SQL} BETWEEN ? AND ?", range.begin.to_i, range.end.to_i)
  end

  def purpose_filter(scope)
    case purpose
    when 'operacional' then scope.where(inbox_id: operational_inbox_ids)
    when 'comercial' then scope.where.not(inbox_id: operational_inbox_ids)
    else scope
    end
  end
end
