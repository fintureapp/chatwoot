# Cotação estruturada do card (Fase 1 CRM Finture). Endpoint único para a aba
# Cotação (source=agent) e para o SDR IA no n8n (source=n8n) — as regras de
# convivência ficam no Finture::QuoteUpsertService. Autenticação do n8n é o
# token de API padrão de um usuário agente.
class Api::V1::Accounts::Conversations::FintureQuotesController < Api::V1::Accounts::Conversations::BaseController
  def show
    render json: serialized_quote(Finture::Quote.find_by(conversation_id: @conversation.id))
  end

  def update
    quote = Finture::QuoteUpsertService.new(
      conversation: @conversation,
      params: quote_params.to_h.symbolize_keys,
      source: source_param,
      temperature: params[:temperature]
    ).perform
    render json: serialized_quote(quote)
  end

  private

  def quote_params
    params.permit(:product_type, :total_value, data: {})
  end

  def source_param
    Finture::Quote::SOURCES.include?(params[:source]) ? params[:source] : 'agent'
  end

  def serialized_quote(quote)
    return { quote: nil } if quote.nil?

    {
      quote: {
        id: quote.id,
        product_type: quote.product_type,
        data: quote.data,
        total_value: quote.total_value&.to_f,
        source: quote.source,
        lives_total: quote.lives_total,
        updated_at: quote.updated_at
      }
    }
  end
end
