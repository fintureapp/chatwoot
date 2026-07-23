# Métricas do Dashboard SDR sobre finture_stage_transitions (+ finture_quotes
# para o ticket médio). Escopo por caixa (inbox_id) ou geral (conta inteira) e
# intervalo de datas [since, until_at] (epoch em segundos; default: 30 dias).
# - leads_identified: leads que entraram no funil no período (conversas criadas)
# - won / lost: leads fechados no período (transições kind won/lost)
# - conversion_rate: won / (won + lost)
# - ticket_medio: média de finture_quotes.total_value dos leads ganhos
# - avg_time_per_stage: tempo médio em cada etapa (diferença entre transições)
class Finture::SdrReportService
  pattr_initialize [:account!, :inbox_id, :since, :until_at]

  def perform
    {
      leads_identified: leads_identified,
      won: won_count,
      lost: lost_count,
      open: open_count,
      conversion_rate: conversion_rate,
      ticket_medio: ticket_medio,
      avg_time_per_stage: avg_time_per_stage
    }
  end

  private

  def range
    @range ||= begin
      from = since.present? ? Time.zone.at(since.to_i) : 30.days.ago
      to = until_at.present? ? Time.zone.at(until_at.to_i) : Time.current
      from..to
    end
  end

  def conversations_scope
    scope = account.conversations
    inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
  end

  def transitions_scope
    scope = Finture::StageTransition.where(account_id: account.id)
    inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
  end

  def leads_identified
    conversations_scope.where(created_at: range).count
  end

  def won_count
    transitions_scope.where(kind: 'won', occurred_at: range).distinct.count(:conversation_id)
  end

  def lost_count
    transitions_scope.where(kind: 'lost', occurred_at: range).distinct.count(:conversation_id)
  end

  def open_count
    conversations_scope.where("custom_attributes ->> 'sdr_outcome' IS NULL").count
  end

  def conversion_rate
    total = won_count + lost_count
    total.zero? ? 0.0 : (won_count.to_f / total).round(4)
  end

  def won_conversation_ids
    transitions_scope.where(kind: 'won', occurred_at: range).distinct.pluck(:conversation_id)
  end

  def ticket_medio
    ids = won_conversation_ids
    return 0.0 if ids.empty?

    Finture::Quote.where(conversation_id: ids).where.not(total_value: nil).average(:total_value)&.to_f || 0.0
  end

  # Tempo por etapa: para cada conversa, o lead ficou na etapa de uma transição
  # até a transição seguinte. Atribui a duração à etapa de origem (só quando a
  # entrada ocorreu dentro do período).
  def avg_time_per_stage
    buckets = Hash.new { |hash, key| hash[key] = [] }
    transitions_by_conversation.each_value do |list|
      list.each_cons(2) do |current, following|
        next unless range.cover?(current.occurred_at)

        buckets[current.to_stage] << (following.occurred_at - current.occurred_at)
      end
    end

    buckets.map do |slug, seconds|
      {
        slug: slug,
        name: stage_names[slug] || slug,
        avg_seconds: (seconds.sum / seconds.size).round
      }
    end.sort_by { |row| stage_positions[row[:slug]] || 999 }
  end

  def transitions_by_conversation
    @transitions_by_conversation ||= transitions_scope
                                     .where(occurred_at: ..range.end)
                                     .order(:conversation_id, :occurred_at, :id)
                                     .group_by(&:conversation_id)
  end

  def pipeline_stages
    @pipeline_stages ||= begin
      scope = Finture::PipelineStage.where(account_id: account.id)
      inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
    end
  end

  def stage_names
    @stage_names ||= pipeline_stages.each_with_object({}) do |stage, memo|
      memo[stage.slug] ||= stage.name
    end
  end

  def stage_positions
    @stage_positions ||= pipeline_stages.each_with_object({}) do |stage, memo|
      memo[stage.slug] ||= stage.position
    end
  end
end
