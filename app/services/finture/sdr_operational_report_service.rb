# Métricas da VISÃO OPERACIONAL do Dashboard SDR. Foco em execução do time e
# higiene do funil — o que precisa de ação agora e onde está o gargalo. Escopo
# por caixa (inbox_id) ou geral, no intervalo [since, until_at].
#
# Nenhum dado novo é necessário — tudo já existe no sistema:
# - follow-ups   → finture_follow_ups (due_at / completed_at)
# - SLA          → first_reply_created_at (1ª resposta humana) menos o instante
#                  em que a label atendimento_humano foi aplicada (taggings)
# - não atrib.   → conversations.assignee_id
# - parados      → conversations.last_activity_at
# - carga        → conversations.created_at / custom_attributes.sdr_stage
# - gargalo      → finture_stage_transitions (+ tempo na etapa atual, sem viés)
#
# O que é snapshot e o que é do período:
# - snapshot (estado AGORA do board): carga do funil e tempo médio por etapa;
# - do período: follow-ups concluídos, SLA, leads sem responsável e parados.
#   Estes três últimos olham só conversas criadas em [since, until_at] — antes
#   varriam a caixa inteira e não batiam com o filtro exibido na tela.
class Finture::SdrOperationalReportService
  include Finture::SdrShared

  pattr_initialize [:account!, :current_user, :inbox_id, :since, :until_at]

  STALLED_AFTER = 7.days
  STALLED_LIMIT = 12

  def perform
    {
      kpis: kpis,
      follow_ups: follow_ups,
      my_follow_ups: my_follow_ups,
      sla: sla,
      load: funnel_load,
      stage_time: stage_time,
      stalled: stalled
    }
  end

  private

  def now
    @now ||= Time.current
  end

  def range
    @range ||= begin
      from = since.present? ? Time.zone.at(since.to_i) : 30.days.ago
      to = until_at.present? ? Time.zone.at(until_at.to_i) : Time.current
      from..to
    end
  end

  # ---- Scopes ---------------------------------------------------------------
  def conversations_scope
    scope = account.conversations
    inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
  end

  # Caixas classificadas como operacionais dentro do escopo consultado. Nelas a
  # demanda sai do board ao ser RESOLVIDA (não há ganho/perdido) — ver
  # Finture::InboxConfig.
  def operational_inbox_ids
    @operational_inbox_ids ||= begin
      scope = Finture::InboxConfig.where(account_id: account.id, kanban_type: 'operacional')
      scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
      scope.pluck(:inbox_id)
    end
  end

  # Leads ativos no board — MESMA regra do Kanban (ver
  # Api::V1::Accounts::ConversationsController#kanban_conversations): comercial
  # fecha por desfecho (sdr_outcome); operacional fecha ao resolver a conversa.
  # Sem o recorte por status o dashboard contava como lead aberto uma demanda já
  # resolvida — daí "leads sem responsável" e "parados há 140 dias" que não
  # apareciam em lugar nenhum da caixa de entrada.
  def open_leads_scope
    scope = conversations_scope.where("custom_attributes ->> 'sdr_outcome' IS NULL")
    return scope if operational_inbox_ids.blank?

    scope.where('conversations.inbox_id NOT IN (?) OR conversations.status <> ?',
                operational_inbox_ids, Conversation.statuses[:resolved])
  end

  # Leads em aberto criados dentro do período selecionado na tela.
  def period_leads_scope
    open_leads_scope.where(created_at: range)
  end

  def transitions_scope
    scope = Finture::StageTransition.where(account_id: account.id)
    inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
  end

  def follow_ups_scope
    scope = Finture::FollowUp.where(account_id: account.id)
    inbox_id.present? ? scope.joins(:conversation).where(conversations: { inbox_id: inbox_id }) : scope
  end

  # ---- KPIs de topo ---------------------------------------------------------
  def kpis
    fu = follow_ups
    {
      overdue_followups: fu[:overdue],
      followups_today: fu[:today],
      unassigned: period_leads_scope.where(assignee_id: nil).count,
      stalled: stalled_scope.count,
      sla_minutes: sla[:avg_minutes]
    }
  end

  # ---- Follow-ups -----------------------------------------------------------
  def follow_ups
    @follow_ups ||= begin
      open = follow_ups_scope.open_items
      completed = follow_ups_scope.where(completed_at: range)
      completed_count = completed.count
      on_time = completed.where('completed_at <= due_at').count
      {
        open: open.count,
        overdue: open.where(due_at: ...now).count,
        today: open.where(due_at: now.beginning_of_day..now.end_of_day).count,
        completed: completed_count,
        on_time_pct: completed_count.zero? ? nil : (on_time.to_f / completed_count).round(4)
      }
    end
  end

  # ---- SLA de 1º contato humano ---------------------------------------------
  # Regra e quebra por área (Time da conversa) em Finture::SdrFirstContactSla.
  def sla
    @sla ||= Finture::SdrFirstContactSla.new(conversations: conversations_scope.where(created_at: range),
                                             team_label: method(:team_name)).perform
  end

  # ---- Carga do funil (snapshot atual) --------------------------------------
  def funnel_load
    raw = open_leads_scope.group(Arel.sql("custom_attributes ->> 'sdr_stage'")).count
    ordered_stages.map do |stage|
      count = raw[stage[:slug]].to_i
      count += raw[nil].to_i if stage[:slug] == default_stage_slug
      { slug: stage[:slug], name: stage[:name], count: count }
    end
  end

  # ---- Gargalo: tempo médio por etapa (com a etapa atual, sem viés) ---------
  # Etapas marcadas como fora do tempo médio (Config da caixa → Funil; no funil
  # operacional Chamada Iniciada e Em Triagem nascem assim) não entram na lista:
  # ali o relógio corre por conta do cliente responder/ser triado, não do nosso
  # atendimento. Elas voltam em `excluded` só para a tela poder dizer o porquê.
  def stage_time
    buckets = stage_time_buckets
    counted, skipped = buckets.keys.partition { |slug| excluded_stage_slugs.exclude?(slug) }
    {
      stages: counted.map { |slug| stage_time_row(slug, buckets[slug]) }.sort_by { |row| stage_positions[row[:slug]] },
      excluded: skipped.sort_by { |slug| stage_positions[slug] }.map { |slug| stage_names[slug] }
    }
  end

  # {slug => [durações em segundos]}, juntando o histórico com a etapa atual.
  def stage_time_buckets
    buckets = Hash.new { |hash, key| hash[key] = [] }

    # Durações já concluídas: intervalo entre transições consecutivas.
    transitions_by_conversation.each_value do |list|
      list.each_cons(2) do |current, following|
        buckets[current.to_stage] << (following.occurred_at - current.occurred_at)
      end
    end

    # Correção do viés de sobrevivência: o lead PARADO agora conta o tempo da
    # última transição (ou da criação) até agora, na etapa atual.
    open_current_stage.each { |slug, last_at| buckets[slug] << (now - last_at) }
    buckets
  end

  def stage_time_row(slug, seconds)
    { slug: slug, name: stage_names[slug], seconds: (seconds.sum / seconds.size).round }
  end

  # Slugs fora do tempo médio. Na visão geral um slug só sai se NENHUMA caixa o
  # contabiliza — assim a configuração de uma caixa não apaga o dado das outras.
  # Slug desconhecido (etapa já removida, ainda presente no histórico) continua.
  def excluded_stage_slugs
    @excluded_stage_slugs ||= pipeline_stages.pluck(:slug, :counts_in_stage_time)
                                             .group_by(&:first)
                                             .reject { |_slug, pairs| pairs.any?(&:last) }
                                             .keys.to_set
  end

  def transitions_by_conversation
    @transitions_by_conversation ||= transitions_scope.order(:conversation_id, :occurred_at, :id)
                                                      .group_by(&:conversation_id)
  end

  # [[slug_atual, timestamp_de_entrada], ...] para os leads em aberto.
  def open_current_stage
    rows = open_leads_scope.pluck(:id, :created_at, Arel.sql("custom_attributes ->> 'sdr_stage'"))
    rows.map do |conv_id, created_at, slug|
      current = slug.presence || default_stage_slug
      last = transitions_by_conversation[conv_id]&.last&.occurred_at || created_at
      [current, last]
    end
  end

  # ---- Leads parados --------------------------------------------------------
  # Só o que ainda está no board (não resolvido, sem desfecho) e foi criado no
  # período — conversa resolvida meses atrás não é "lead parado", é histórico.
  def stalled_scope
    period_leads_scope.where('last_activity_at < ?', now - STALLED_AFTER)
  end

  def stalled
    stalled_scope.order(:last_activity_at).limit(STALLED_LIMIT)
                 .includes(:contact, :assignee).map do |conversation|
      attrs = conversation.custom_attributes || {}
      slug = attrs['sdr_stage'].presence || default_stage_slug
      {
        id: conversation.display_id,
        contact: conversation.contact&.name,
        product: team_name(conversation.team_id),
        stage: stage_names[slug],
        days: ((now - conversation.last_activity_at) / 86_400.0).floor,
        assignee: conversation.assignee&.name
      }
    end
  end

  # ---- Etapas (nome / posição por slug) -------------------------------------
  def pipeline_stages
    @pipeline_stages ||= begin
      scope = Finture::PipelineStage.where(account_id: account.id)
      inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
    end
  end

  def ordered_stages
    if inbox_id.present?
      pipeline_stages.ordered.map { |stage| { slug: stage.slug, name: stage.name } }
    else
      Finture::PipelineStage::DEFAULT_STAGES.map { |attrs| { slug: attrs[:slug], name: attrs[:name] } }
    end
  end

  # Etapa de entrada do funil DA CAIXA — é nela que cai o lead sem sdr_stage. No
  # funil operacional isso é "Chamada Iniciada"; assumir sempre o lead_identificado
  # do funil comercial fazia esses leads sumirem da carga e virarem uma etapa
  # fantasma no tempo médio. Sem caixa (visão geral) vale o slug canônico.
  def default_stage_slug
    @default_stage_slug ||= (inbox_id.present? && ordered_stages.first&.fetch(:slug, nil)) ||
                            Finture::PipelineStage::DEFAULT_SLUG
  end

  # Mapas por slug, com fallback embutido para a etapa já removida da caixa mas
  # ainda presente no histórico: mostra o próprio slug, no fim da ordem. O
  # `reverse` faz a 1ª ocorrência vencer quando a visão geral junta várias caixas.
  def stage_names
    @stage_names ||= Hash.new { |_, slug| slug }.merge(pipeline_stages.pluck(:slug, :name).reverse.to_h)
  end

  def stage_positions
    @stage_positions ||= Hash.new(999).merge(pipeline_stages.pluck(:slug, :position).reverse.to_h)
  end
end
