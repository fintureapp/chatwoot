# Métricas da VISÃO COMERCIAL do Dashboard SDR (repaginação: comercial x
# operacional). Foco em resultado do funil — sem valor arrecadado (receita/
# pipeline ficam na outra plataforma, decisão de produto). Escopo por caixa
# (inbox_id) ou geral, no intervalo [since, until_at] (epoch em segundos), com
# uma janela de comparação ajustável ([compare_since, compare_until]; default:
# a janela imediatamente anterior, de mesmo tamanho).
#
# Retorna:
# - kpis:         conversão, leads, ganhos e ciclo médio (valor + janela de
#                 comparação + delta)
# - funnel:       nº de leads que alcançaram cada etapa no período (+ Ganho)
# - mix:          leads por produto (custom_attributes.produto_interesse), top 6
# - loss_reasons: motivos de perda (transições kind=lost), do mais frequente
# - trend:        série temporal de leads e ganhos (bucket diário ou semanal) +
#                 série de leads da janela de comparação (linha fantasma)
# - velocity:     dias até ganho (geral e por produto)
class Finture::SdrCommercialReportService
  pattr_initialize [:account!, :inbox_id, :since, :until_at, :compare_since, :compare_until]

  TOP_PRODUCTS = 6

  def perform
    {
      kpis: kpis,
      funnel: funnel,
      mix: mix,
      loss_reasons: loss_reasons,
      trend: trend,
      velocity: velocity
    }
  end

  private

  # ---- Janelas de tempo -----------------------------------------------------
  def range
    @range ||= begin
      from = since.present? ? Time.zone.at(since.to_i) : 30.days.ago
      to = until_at.present? ? Time.zone.at(until_at.to_i) : Time.current
      from..to
    end
  end

  # Comparação: janela explícita (filtro "Comparar com") ou a janela anterior de
  # mesmo tamanho, quando não informada.
  def compare_range
    @compare_range ||= begin
      if compare_since.present? && compare_until.present?
        Time.zone.at(compare_since.to_i)..Time.zone.at(compare_until.to_i)
      else
        span = range.end - range.begin
        (range.begin - span)..range.begin
      end
    end
  end

  # ---- Scopes ---------------------------------------------------------------
  def conversations_scope
    scope = account.conversations
    inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
  end

  def transitions_scope
    scope = Finture::StageTransition.where(account_id: account.id)
    inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
  end

  # ---- KPIs -----------------------------------------------------------------
  def kpis
    cur = window_metrics(range)
    prev = window_metrics(compare_range)
    {
      conversion: kpi(cur[:conversion], prev[:conversion]),
      leads: kpi(cur[:leads], prev[:leads]),
      won: kpi(cur[:won], prev[:won]),
      cycle_days: kpi(cur[:cycle_days], prev[:cycle_days])
    }
  end

  def kpi(value, previous)
    delta = value && previous ? (value - previous).round(4) : nil
    { value: value, previous: previous, delta: delta }
  end

  def window_metrics(window)
    won = won_latest_map(window).size
    lost = transitions_scope.where(kind: 'lost', occurred_at: window).distinct.count(:conversation_id)
    total = won + lost
    {
      leads: conversations_scope.where(created_at: window).count,
      won: won,
      lost: lost,
      conversion: total.zero? ? 0.0 : (won.to_f / total).round(4),
      cycle_days: avg_cycle_days(window)
    }
  end

  # {conversation_id => data do último ganho na janela}. Uma conversa reaberta e
  # ganha de novo conta uma vez, pelo ganho mais recente.
  def won_latest_map(window)
    (@won_latest ||= {})[window] ||= begin
      pairs = transitions_scope.where(kind: 'won', occurred_at: window)
                               .order(:conversation_id, occurred_at: :desc)
                               .pluck(:conversation_id, :occurred_at)
      pairs.each_with_object({}) { |(conv_id, occurred), memo| memo[conv_id] ||= occurred }
    end
  end

  # Pares [won_at, created_at] das conversas ganhas na janela (para o ciclo).
  def won_pairs(window)
    map = won_latest_map(window)
    return [] if map.empty?

    created = conversations_scope.where(id: map.keys).pluck(:id, :created_at).to_h
    map.filter_map { |conv_id, won_at| [won_at, created[conv_id]] if created[conv_id] }
  end

  def avg_cycle_days(window)
    pairs = won_pairs(window)
    return 0.0 if pairs.empty?

    total = pairs.sum { |won_at, created_at| won_at - created_at }
    (total / pairs.size / 86_400.0).round(1)
  end

  # ---- Funil ----------------------------------------------------------------
  def funnel
    nodes = ordered_stages.map do |stage|
      count = if stage[:slug] == Finture::PipelineStage::DEFAULT_SLUG
                conversations_scope.where(created_at: range).count
              else
                transitions_scope.where(to_stage: stage[:slug], occurred_at: range)
                                 .distinct.count(:conversation_id)
              end
      { slug: stage[:slug], name: stage[:name], count: count }
    end
    nodes << { slug: 'ganho', name: 'Ganho', count: won_latest_map(range).size }
    nodes
  end

  # Etapas do funil na ordem. Com caixa: as etapas configuradas dela. Geral: os
  # slugs canônicos (nomes variam por caixa, os slugs não — ver histórico).
  def ordered_stages
    if inbox_id.present?
      Finture::PipelineStage.where(account_id: account.id, inbox_id: inbox_id)
                            .ordered.map { |stage| { slug: stage.slug, name: stage.name } }
    else
      Finture::PipelineStage::DEFAULT_STAGES.map { |attrs| { slug: attrs[:slug], name: attrs[:name] } }
    end
  end

  # ---- Mix por produto ------------------------------------------------------
  def mix
    raw = conversations_scope.where(created_at: range)
                             .group(Arel.sql("custom_attributes ->> 'produto_interesse'"))
                             .count
    rows = raw.map { |product, count| { product: product.presence || 'Não informado', count: count } }
                .sort_by { |row| -row[:count] }
    return rows if rows.size <= TOP_PRODUCTS

    rest = rows.drop(TOP_PRODUCTS).sum { |row| row[:count] }
    rows.first(TOP_PRODUCTS) + [{ product: 'Outros', count: rest }]
  end

  # ---- Motivos de perda -----------------------------------------------------
  def loss_reasons
    transitions_scope.where(kind: 'lost', occurred_at: range)
                     .group(:reason).count
                     .map { |reason, count| { reason: reason.presence || 'nao_informado', count: count } }
                     .sort_by { |row| -row[:count] }
  end

  # ---- Tendência ------------------------------------------------------------
  def trend
    unit = span_days(range) <= 31 ? 'day' : 'week'
    current = trend_series(range, unit)
    compare = trend_series(compare_range, unit)
    {
      unit: unit,
      buckets: current,
      compare: compare.map { |bucket| { label: bucket[:label], leads: bucket[:leads] } }
    }
  end

  def trend_series(window, unit)
    labels = bucket_labels(window, unit)
    leads = Array.new(labels.size, 0)
    ganhos = Array.new(labels.size, 0)

    conversations_scope.where(created_at: window).pluck(:created_at).each do |timestamp|
      leads[bucket_index(timestamp, window.begin, unit, labels.size)] += 1
    end
    transitions_scope.where(kind: 'won', occurred_at: window).pluck(:occurred_at).each do |timestamp|
      ganhos[bucket_index(timestamp, window.begin, unit, labels.size)] += 1
    end

    labels.each_with_index.map { |label, index| { label: label, leads: leads[index], ganhos: ganhos[index] } }
  end

  def bucket_labels(window, unit)
    step = unit == 'day' ? 1 : 7
    count = (span_days(window) / step.to_f).ceil
    (0..count).map { |index| (window.begin.to_date + (index * step)).strftime('%d/%m') }
  end

  def bucket_index(timestamp, window_begin, unit, size)
    days = (timestamp.to_date - window_begin.to_date).to_i
    index = unit == 'day' ? days : days / 7
    index.clamp(0, size - 1)
  end

  def span_days(window)
    ((window.end - window.begin) / 86_400.0).ceil
  end

  # ---- Velocidade -----------------------------------------------------------
  def velocity
    { overall_days: avg_cycle_days(range), by_product: velocity_by_product }
  end

  def velocity_by_product
    map = won_latest_map(range)
    return [] if map.empty?

    rows = conversations_scope.where(id: map.keys)
                              .pluck(:id, :created_at, Arel.sql("custom_attributes ->> 'produto_interesse'"))
    buckets = Hash.new { |hash, key| hash[key] = [] }
    rows.each do |conv_id, created_at, product|
      won_at = map[conv_id]
      buckets[product.presence || 'Não informado'] << (won_at - created_at) if won_at && created_at
    end

    buckets.map { |product, seconds| { product: product, days: (seconds.sum / seconds.size / 86_400.0).round(1) } }
           .sort_by { |row| row[:days] }
  end
end
