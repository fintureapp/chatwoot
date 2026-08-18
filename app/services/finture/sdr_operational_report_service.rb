# Métricas da VISÃO OPERACIONAL do Dashboard SDR. Foco em execução do time e
# higiene do funil — o que precisa de ação agora e onde está o gargalo. Escopo
# por caixa (inbox_id) ou geral. Algumas métricas são snapshot (estado atual:
# carga, aging, não atribuídos, parados) e outras são do período [since,
# until_at] (follow-ups concluídos, SLA de 1º contato).
#
# Nenhum dado novo é necessário — tudo já existe no sistema:
# - follow-ups   → finture_follow_ups (due_at / completed_at)
# - SLA          → conversations.first_reply_created_at (nativo)
# - não atrib.   → conversations.assignee_id
# - parados      → conversations.last_activity_at
# - aging/carga  → conversations.created_at / custom_attributes.sdr_stage
# - gargalo      → finture_stage_transitions (+ tempo na etapa atual, sem viés)
class Finture::SdrOperationalReportService
  pattr_initialize [:account!, :inbox_id, :since, :until_at]

  STALLED_AFTER = 7.days
  STALLED_LIMIT = 12

  def perform
    {
      kpis: kpis,
      follow_ups: follow_ups,
      sla: sla,
      load: funnel_load,
      aging: aging,
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

  # Leads ativos no board = conversas sem desfecho (mesma regra do Kanban SDR).
  def open_leads_scope
    conversations_scope.where("custom_attributes ->> 'sdr_outcome' IS NULL")
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
      unassigned: open_leads_scope.where(assignee_id: nil).count,
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

  # ---- SLA de 1º contato ----------------------------------------------------
  def sla
    @sla ||= begin
      rows = conversations_scope.where(created_at: range)
                                .where.not(first_reply_created_at: nil)
                                .pluck(:created_at, :first_reply_created_at,
                                       Arel.sql("custom_attributes ->> 'produto_interesse'"))
      {
        avg_minutes: avg_minutes(rows.map { |created, replied, _| replied - created }),
        by_product: sla_by_product(rows)
      }
    end
  end

  def sla_by_product(rows)
    buckets = Hash.new { |hash, key| hash[key] = [] }
    rows.each { |created, replied, product| buckets[product.presence || 'Não informado'] << (replied - created) }
    buckets.map { |product, seconds| { product: product, minutes: avg_minutes(seconds) } }
           .sort_by { |row| row[:minutes] }
  end

  def avg_minutes(seconds)
    return nil if seconds.empty?

    (seconds.sum / seconds.size / 60.0).round
  end

  # ---- Carga do funil (snapshot atual) --------------------------------------
  def funnel_load
    raw = open_leads_scope.group(Arel.sql("custom_attributes ->> 'sdr_stage'")).count
    ordered_stages.map do |stage|
      count = raw[stage[:slug]].to_i
      # leads sem sdr_stage caem na 1ª etapa (Lead Identificado).
      count += raw[nil].to_i if stage[:slug] == Finture::PipelineStage::DEFAULT_SLUG
      { slug: stage[:slug], name: stage[:name], count: count }
    end
  end

  # ---- Aging (idade dos leads em aberto) ------------------------------------
  def aging
    days = open_leads_scope.pluck(:created_at).map { |created| ((now - created) / 86_400.0) }
    {
      fresh: days.count { |d| d <= 3 },       # 0–3 dias
      warm: days.count { |d| d > 3 && d <= 7 }, # 4–7 dias
      stale: days.count { |d| d > 7 }           # +7 dias
    }
  end

  # ---- Gargalo: tempo médio por etapa (com a etapa atual, sem viés) ---------
  def stage_time
    buckets = Hash.new { |hash, key| hash[key] = [] }

    # Durações já concluídas: intervalo entre transições consecutivas.
    transitions_by_conversation.each_value do |list|
      list.each_cons(2) do |current, following|
        buckets[current.to_stage] << (following.occurred_at - current.occurred_at)
      end
    end

    # Correção do viés de sobrevivência: o lead PARADO agora conta o tempo da
    # última transição (ou da criação) até agora, na etapa atual.
    open_current_stage.each do |slug, last_at|
      buckets[slug] << (now - last_at)
    end

    buckets.map do |slug, seconds|
      { slug: slug, name: stage_names[slug] || slug, seconds: (seconds.sum / seconds.size).round }
    end.sort_by { |row| stage_positions[row[:slug]] || 999 }
  end

  def transitions_by_conversation
    @transitions_by_conversation ||= transitions_scope.order(:conversation_id, :occurred_at, :id)
                                                       .group_by(&:conversation_id)
  end

  # {conversation_id => [slug_atual, timestamp_de_entrada]} para leads em aberto.
  def open_current_stage
    rows = open_leads_scope.pluck(:id, :created_at, Arel.sql("custom_attributes ->> 'sdr_stage'"))
    rows.map do |conv_id, created_at, slug|
      current = slug.presence || Finture::PipelineStage::DEFAULT_SLUG
      last = transitions_by_conversation[conv_id]&.last&.occurred_at || created_at
      [current, last]
    end
  end

  # ---- Leads parados --------------------------------------------------------
  def stalled_scope
    open_leads_scope.where('last_activity_at < ?', now - STALLED_AFTER)
  end

  def stalled
    stalled_scope.order(:last_activity_at).limit(STALLED_LIMIT)
                 .includes(:contact, :assignee).map do |conversation|
      attrs = conversation.custom_attributes || {}
      slug = attrs['sdr_stage'].presence || Finture::PipelineStage::DEFAULT_SLUG
      {
        id: conversation.display_id,
        contact: conversation.contact&.name,
        product: attrs['produto_interesse'],
        stage: stage_names[slug] || slug,
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

  def stage_names
    @stage_names ||= pipeline_stages.each_with_object({}) { |stage, memo| memo[stage.slug] ||= stage.name }
  end

  def stage_positions
    @stage_positions ||= pipeline_stages.each_with_object({}) { |stage, memo| memo[stage.slug] ||= stage.position }
  end
end
