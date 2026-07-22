# Upsert da cotação do card com as regras de convivência IA/humano da Fase 1:
# - source 'agent' (aba Cotação): sobrescreve livremente — edição humana manda;
# - source 'n8n' (SDR IA): SÓ preenche o que está vazio — nunca desfaz edição
#   humana; temperatura vira prioridade da conversa apenas se ela for nula.
# Em ambos: total_value sugere o custom attribute valor_potencial só se ele
# estiver vazio ("sugerir sem amarrar") e o resumo é espelhado em
# custom_attributes['sdr_quote_summary'] — uma única gravação na conversa, que
# reaproveita broadcast/payload que o board já tem.
class Finture::QuoteUpsertService
  MIRROR_KEY = 'sdr_quote_summary'.freeze
  PRODUCT_LABELS = {
    'saude_pme' => 'Saúde PME',
    'consorcio' => 'Consórcio',
    'seguros' => 'Seguros',
    'credito' => 'Crédito'
  }.freeze
  TEMPERATURE_PRIORITIES = { 'quente' => 'high', 'morno' => 'medium', 'frio' => 'low' }.freeze

  pattr_initialize [:conversation!, :params!, :source!, :temperature]

  def perform
    @quote = Finture::Quote.find_or_initialize_by(conversation_id: conversation.id) do |quote|
      quote.account_id = conversation.account_id
    end
    ai_source? ? apply_fill_empty : apply_overwrite
    @quote.source = source
    @quote.save!
    apply_temperature
    sync_conversation
    @quote
  end

  private

  attr_reader :quote

  def ai_source?
    source == 'n8n'
  end

  def apply_overwrite
    @quote.product_type = params[:product_type] if params.key?(:product_type)
    @quote.total_value = params[:total_value] if params.key?(:total_value)
    @quote.data = (@quote.data || {}).merge(params[:data]) if params[:data].is_a?(Hash)
  end

  # IA nunca sobrescreve: product_type só em cotação nova, total_value só se
  # vazio e, dentro de data, apenas as chaves ainda não preenchidas.
  def apply_fill_empty
    @quote.product_type = params[:product_type] if @quote.new_record? && params.key?(:product_type)
    @quote.total_value = params[:total_value] if @quote.total_value.blank? && params.key?(:total_value)
    return unless params[:data].is_a?(Hash)

    existing = @quote.data || {}
    fresh = params[:data].reject { |key, _| existing[key].present? }
    @quote.data = existing.merge(fresh)
  end

  def apply_temperature
    return unless ai_source? && temperature.present? && conversation.priority.nil?

    priority = TEMPERATURE_PRIORITIES[temperature.to_s.downcase] || (temperature if Conversation.priorities.key?(temperature))
    conversation.toggle_priority(priority) if priority
  end

  def sync_conversation
    attrs = conversation.custom_attributes || {}
    attrs[MIRROR_KEY] = summary
    attrs['valor_potencial'] = quote.total_value.to_f if suggest_valor_potencial?(attrs)
    conversation.update!(custom_attributes: attrs)
  end

  def suggest_valor_potencial?(attrs)
    quote.total_value.present? && attrs['valor_potencial'].blank?
  end

  def summary
    parts = [PRODUCT_LABELS[quote.product_type]]
    parts << "#{quote.lives_total} vidas" if quote.product_type == 'saude_pme' && quote.lives_total.positive?
    if quote.total_value.present?
      parts << ActiveSupport::NumberHelper.number_to_currency(quote.total_value, unit: 'R$ ', separator: ',', delimiter: '.')
    end
    parts.compact.join(' · ')
  end
end
