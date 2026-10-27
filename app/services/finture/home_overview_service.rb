# Home, a tela de entrada (card "Home admin" do Chatwoot V3, aberta a todos os
# usuários). Tudo sai do que já está instrumentado — nada é estimado, e todo
# usuário vê a conta inteira (Finture::HomeScopes).
#
# - destaques: o que chegou, foi resolvido e ganho no período (eventos), com o
#   mesmo recorte do período anterior para comparar, mais o funil comercial em
#   aberto e as conversas com a IA agora (estoque);
# - série por dia (por hora em "hoje") de chegadas e resoluções (Finture::HomeSeries);
# - carga por equipe: os mesmos times do wallboard (todos os times da conta +
#   "Sem time"), com o estoque de agora e os eventos do período;
# - 1º contato humano (SLA) e motivos de perda do período.
#
# Métrica sem fonte confiável volta `nil` (a tela mostra "indisponível", nunca 0).
# Cada número tem uma lista (`drilldown`) lida do MESMO escopo
# (Finture::HomeScopes), então o total do cartão é o total da lista.
#
# Filtros: caixa, finalidade (comercial/operacional — Finture::InboxConfig),
# equipe (team_id; 'none' = sem time) e período (today/7/30 dias). O controller
# fixa o fuso em America/Sao_Paulo.
class Finture::HomeOverviewService
  TIME_ZONE = 'America/Sao_Paulo'.freeze
  PERIOD_DAYS = { 'today' => 0, '7' => 6, '30' => 29 }.freeze
  DEFAULT_PERIOD = '7'.freeze
  LIST_LIMIT = 50
  METRICS = Finture::HomeScopes::METRICS
  # coluna da carga por equipe => escopo (Finture::HomeScopes)
  TEAM_COLUMNS = {
    attending: :attending_scope, unassigned: :unassigned_scope, waiting_reply: :waiting_scope,
    entered: :entered_scope, resolved: :resolved_scope
  }.freeze

  pattr_initialize [:account!, :current_user!, :inbox_id, :team_id, :purpose, :period]

  def perform
    {
      generated_at: now.to_i,
      time_zone: TIME_ZONE,
      period: { key: period_key, since: range.begin.to_i, until: range.end.to_i },
      highlights: highlights_block,
      previous: previous_block,
      series: Finture::HomeSeries.new(scopes: scopes, range: range, hourly: period_key == 'today').perform,
      teams: teams_block,
      sla: Finture::SdrFirstContactSla.new(conversations: scopes.entered_scope, team_label: scopes.method(:team_name)).perform,
      lost: lost_block
    }
  end

  def drilldown(metric)
    scope = scopes.metric(metric)
    items = scope.includes(:contact, :assignee, :inbox).order(list_order(metric)).limit(LIST_LIMIT)
    { metric: metric, total: scope.count, items: items.map { |conversation| conversation_item(conversation) } }
  end

  private

  def now
    @now ||= Time.current
  end

  def period_key
    PERIOD_DAYS.key?(period.to_s) ? period.to_s : DEFAULT_PERIOD
  end

  def range
    @range ||= (now - PERIOD_DAYS[period_key].days).beginning_of_day..now
  end

  def scopes
    @scopes ||= build_scopes(range, now)
  end

  # Período anterior de mesmo tamanho, até a mesma hora: "hoje até agora" contra
  # "ontem até a mesma hora"; "7 dias" contra os 7 dias antes deles.
  def previous_range
    shift = (PERIOD_DAYS[period_key] + 1).days
    @previous_range ||= (range.begin - shift)..(now - shift)
  end

  def previous_scopes
    @previous_scopes ||= build_scopes(previous_range, previous_range.end)
  end

  def build_scopes(scope_range, scope_now)
    Finture::HomeScopes.new(account: account, current_user: current_user, inbox_id: inbox_id,
                            team_id: team_id, purpose: purpose, range: scope_range, now: scope_now)
  end

  def commercial?
    purpose != 'operacional'
  end

  def count(metric)
    scopes.metric(metric).count
  end

  # ---- Destaques ------------------------------------------------------------
  # Ganho e funil só existem no comercial: na finalidade operacional voltam nil.
  def highlights_block
    {
      entered: count('entered'),
      resolved: count('resolved'),
      won: commercial? ? { count: count('won'), **scopes.volume(scopes.won_scope) } : nil,
      pipeline: commercial? ? { count: count('pipeline_open'), **scopes.volume(scopes.pipeline_open_scope) } : nil,
      with_ai: scopes.ai_inbox_ids.empty? ? nil : count('with_ai')
    }
  end

  # Os mesmos eventos no período anterior (só o que é evento; estoque não compara).
  def previous_block
    {
      since: previous_range.begin.to_i,
      entered: previous_scopes.entered_scope.count,
      resolved: previous_scopes.resolved_scope.count,
      won_value: commercial? ? previous_scopes.volume(previous_scopes.won_scope)[:value] : nil
    }
  end

  # ---- Carga por equipe -----------------------------------------------------
  # Mesmo universo e ordem do wallboard: todos os times da conta (mesmo zerados),
  # "Sem time" por último e só quando tem conversa; entre times, mais conversas
  # em atendimento primeiro, depois mais operadores online, depois o nome.
  def teams_block
    rows = team_rows.reject { |row| no_team?(row) && TEAM_COLUMNS.keys.all? { |key| row[key].zero? } }
    rows.sort_by { |row| [no_team?(row) ? 1 : 0, -row[:attending], -row[:online], row[:name]] }
  end

  def team_rows
    counts = TEAM_COLUMNS.transform_values { |scope| scopes.public_send(scope).group(:team_id).count }
    oldest = scopes.waiting_scope.group(:team_id).minimum(:waiting_since)
    online = online_by_team
    team_ids.map { |id| team_row(id, counts, online, oldest[id]) }
  end

  def no_team?(row)
    row[:team_id] == Finture::HomeScopes::NO_TEAM
  end

  def team_ids
    return [team_id == Finture::HomeScopes::NO_TEAM ? nil : team_id.to_i] if team_id.present?

    account.teams.pluck(:id) + [nil]
  end

  def team_row(id, counts, online, oldest_waiting)
    row = counts.transform_values { |by_team| by_team[id].to_i }
    row.merge(team_id: id || Finture::HomeScopes::NO_TEAM, name: scopes.team_name(id),
              online: id ? online[id].to_i : 0, oldest_waiting_since: oldest_waiting&.to_i)
  end

  # Operadores online pelo time principal (o de menor id, como no wallboard),
  # para um agente em dois times não contar duas vezes.
  def online_by_team
    online_ids = OnlineStatusTracker.get_available_users(account.id).select { |_id, status| status == 'online' }.keys.map(&:to_i)
    return {} if online_ids.empty?

    TeamMember.joins(:team).where(teams: { account_id: account.id }, user_id: online_ids)
              .group(:user_id).minimum(:team_id).values.tally
  end

  # ---- Motivos de perda (perdidos no período) -------------------------------
  def lost_block
    return nil unless commercial?

    { total: count('lost'), reasons: lost_reasons }
  end

  def lost_reasons
    reasons = scopes.lost_scope.group(Arel.sql("conversations.custom_attributes ->> 'sdr_lost_reason'")).count
    reasons.sort_by { |_reason, total| -total }.first(5).map { |reason, total| { reason: reason, count: total } }
  end

  # ---- Listas ----------------------------------------------------------------
  # Mais antigo primeiro onde a pergunta é "o que precisa de ação"; ganho e
  # perdido pelo desfecho mais recente.
  def list_order(metric)
    case metric
    when 'waiting_reply' then { waiting_since: :asc }
    when 'attending', 'unassigned', 'with_ai' then { last_activity_at: :asc }
    when 'won', 'lost' then Arel.sql("#{Finture::HomeScopes::OUTCOME_AT_SQL} DESC")
    when 'pipeline_open' then Arel.sql("#{Finture::HomeScopes::VALUE_SQL} DESC NULLS LAST")
    else { created_at: :desc }
    end
  end

  def conversation_item(conversation)
    {
      id: conversation.display_id,
      contact: conversation.contact&.name,
      inbox: conversation.inbox&.name,
      team: scopes.team_name(conversation.team_id),
      assignee: conversation.assignee&.name,
      status: conversation.status,
      waiting_since: conversation.waiting_since&.to_i,
      last_activity_at: conversation.last_activity_at&.to_i,
      created_at: conversation.created_at.to_i
    }.merge(deal_fields(conversation.custom_attributes || {}))
  end

  # Valor com a mesma regra de Finture::HomeScopes::VALUE_SQL.
  def deal_fields(attrs)
    text = attrs['valor_potencial'].to_s.strip
    {
      value: text.match?(/\A-?\d+(\.\d+)?\z/) ? text.to_f : nil,
      outcome_at: attrs['sdr_outcome_at'].presence&.to_i
    }
  end
end
