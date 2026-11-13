# Cliente HTTP do HUB Finture (Dash-Inteligente-Finture) usado pela Central de
# Demandas. Fala com o ingest `POST /api/v1/demandas/ingest`, protegido por
# segredo compartilhado no cabeçalho `X-Ingest-Secret`. Tudo por variável de
# ambiente; sem as duas a integração fica desligada:
#
#   FINTURE_HUB_BASE_URL        ex.: https://finture-api.azurewebsites.net
#   FINTURE_HUB_INGEST_SECRET   mesmo valor de DEMANDAS_INGEST_SECRET no HUB
#
# Erro passageiro (rede, 429, 5xx — inclui o 503 "not_configured" do HUB)
# levanta TransientError, para o job tentar de novo; o resto (400/401/422)
# levanta Error e não é retentado.
class Finture::HubClient
  class Error < StandardError; end
  class TransientError < Error; end

  INGEST_PATH = '/api/v1/demandas/ingest'.freeze
  TIMEOUT = 15
  OPEN_TIMEOUT = 5

  def self.configured?
    base_url.present? && secret.present?
  end

  def self.base_url
    ENV.fetch('FINTURE_HUB_BASE_URL', '').to_s.strip.chomp('/')
  end

  def self.secret
    ENV.fetch('FINTURE_HUB_INGEST_SECRET', '').to_s.strip
  end

  # Cria ou atualiza a demanda no HUB (UPSERT por external_id). Devolve o corpo
  # JSON da resposta ({ "demanda" => {...}, "criada" => bool, ... }).
  def upsert_demanda(payload)
    raise Error, 'FINTURE_HUB_BASE_URL/FINTURE_HUB_INGEST_SECRET não configurados' unless self.class.configured?

    response = connection.post("#{self.class.base_url}#{INGEST_PATH}") do |req|
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept'] = 'application/json'
      req.headers['X-Ingest-Secret'] = self.class.secret
      req.body = payload.to_json
    end
    handle(response)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise TransientError, "#{e.class}: #{e.message}"
  end

  private

  def handle(response)
    status = response.status
    raise TransientError, "HTTP #{status}: #{response.body.to_s.truncate(300)}" if status == 429 || status >= 500
    raise Error, "HTTP #{status}: #{response.body.to_s.truncate(300)}" unless status.between?(200, 299)

    body = response.body.to_s
    body.blank? ? {} : JSON.parse(body)
  rescue JSON::ParserError => e
    raise Error, "resposta inválida do HUB: #{e.message}"
  end

  def connection
    Faraday.new do |f|
      f.options.timeout = TIMEOUT
      f.options.open_timeout = OPEN_TIMEOUT
    end
  end
end
