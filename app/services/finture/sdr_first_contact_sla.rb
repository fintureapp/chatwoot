# SLA de 1º contato humano do Dashboard SDR. Conta do momento em que a conversa
# entra em atendimento humano (label atendimento_humano aplicada) até a 1ª
# resposta de um agente humano — first_reply_created_at só é setado por sender
# User, bot/AgentBot não contam. Sem a label, ou com a resposta anterior a ela,
# não há SLA a medir: a conversa entra no total e fica fora da média.
#
# TODA área com volume no período entra na quebra, mesmo sem nenhuma conversa
# mensurável (minutes: nil). Antes a área sumia da lista inteira e a tela dava a
# impressão de que só existiam duas. `measured`/`total` expõem o tamanho da
# amostra — é o que separa "1 min de média" de "1 min em 1 conversa de 40".
class Finture::SdrFirstContactSla
  # Tempo-alvo até o 1º contato humano (minutos). Referência exibida no card.
  TARGET_MINUTES = 45
  HUMAN_LABEL = 'atendimento_humano'.freeze

  # conversations: escopo já recortado (caixa + período).
  # team_label:    callable {team_id => rótulo da área} (ver Finture::SdrShared).
  pattr_initialize [:conversations!, :team_label!]

  def perform
    durations = []
    buckets = Hash.new { |hash, key| hash[key] = { seconds: [], total: 0 } }

    rows.each do |conv_id, replied, team_id|
      bucket = buckets[team_label.call(team_id)]
      bucket[:total] += 1
      seconds = measured_seconds(replied, tag_times[conv_id])
      next if seconds.nil?

      durations << seconds
      bucket[:seconds] << seconds
    end

    summary(durations, buckets)
  end

  def self.avg_minutes(seconds)
    return nil if seconds.empty?

    (seconds.sum / seconds.size / 60.0).round
  end

  private

  def rows
    @rows ||= conversations.pluck(:id, :first_reply_created_at, :team_id)
  end

  def summary(durations, buckets)
    {
      avg_minutes: self.class.avg_minutes(durations),
      target_minutes: TARGET_MINUTES,
      measured: durations.size,
      total: rows.size,
      by_product: by_team(buckets)
    }
  end

  def by_team(buckets)
    buckets.map do |team, data|
      {
        product: team,
        minutes: self.class.avg_minutes(data[:seconds]),
        measured: data[:seconds].size,
        total: data[:total]
      }
    end.sort_by { |row| row[:minutes] || Float::INFINITY }
  end

  def measured_seconds(replied, tagged_at)
    return nil if replied.nil? || tagged_at.nil?

    seconds = replied - tagged_at
    seconds.negative? ? nil : seconds
  end

  def tag_times
    @tag_times ||= human_label_times
  end

  # {conversation_id => 1ª aplicação da label atendimento_humano}.
  def human_label_times
    tag = ActsAsTaggableOn::Tag.find_by(name: HUMAN_LABEL)
    ids = rows.map(&:first)
    return {} if tag.nil? || ids.blank?

    ActsAsTaggableOn::Tagging
      .where(tag_id: tag.id, taggable_type: 'Conversation', context: 'labels', taggable_id: ids)
      .group(:taggable_id).minimum(:created_at)
  end
end
