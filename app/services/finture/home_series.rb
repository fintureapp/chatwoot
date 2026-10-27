# Série do gráfico "Chegadas e resoluções" da Home (Finture::HomeOverviewService):
# quantas conversas chegaram e quantas foram resolvidas em cada dia do período
# (ou em cada hora, no período "hoje"), no fuso corrente (America/Sao_Paulo).
#
# Lê os mesmos escopos dos cards, então a soma da série é o número do card. Uma
# conversa resolvida duas vezes no período conta uma vez, no dia da última
# resolução — como no card "Resolvidas".
class Finture::HomeSeries
  pattr_initialize [:scopes!, :range!, :hourly!]

  def perform
    entered = tally(scopes.entered_scope.pluck(:created_at))
    resolved = tally(scopes.resolution_times)
    points = buckets.map { |bucket| { at: bucket.to_i, entered: entered[bucket].to_i, resolved: resolved[bucket].to_i } }
    { granularity: hourly ? 'hour' : 'day', points: points }
  end

  private

  def tally(times)
    times.map { |time| bucket_of(time) }.tally
  end

  def bucket_of(time)
    local = time.in_time_zone
    hourly ? local.beginning_of_hour : local.beginning_of_day
  end

  def buckets
    step = hourly ? 1.hour : 1.day
    first = bucket_of(range.begin)
    last = bucket_of(range.end)
    Array.new((((last - first) / step).round + 1)) { |index| first + (index * step) }
  end
end
