require 'faraday/multipart'

# Cliente do motor de transcrição (speech-to-text) usado pelo
# Finture::AudioTranscriptionService. Fala com a API de transcrição no formato
# OpenAI, hospedada na Azure OpenAI (padrão: os dados ficam na nossa assinatura)
# ou na OpenAI direto. Tudo por variável de ambiente:
#
#   FINTURE_TRANSCRIPTION_PROVIDER     azure (padrão) | openai
#   FINTURE_TRANSCRIPTION_API_KEY      chave da API (sem ela a transcrição fica desligada)
#   FINTURE_TRANSCRIPTION_ENDPOINT     azure: https://<recurso>.openai.azure.com
#                                      openai: https://api.openai.com/v1 (padrão)
#   FINTURE_TRANSCRIPTION_MODEL        modelo (openai) ou nome do deployment (azure);
#                                      padrão gpt-4o-mini-transcribe
#   FINTURE_TRANSCRIPTION_API_VERSION  só azure; padrão 2025-03-01-preview
#   FINTURE_TRANSCRIPTION_PROMPT       vocabulário de apoio (substitui o padrão)
#   FINTURE_TRANSCRIPTION_LOGPROBS     false desliga o pedido de logprobs (confiança)
#
# Devolve { text:, confidence: (0..1 ou nil), engine: }. Erro passageiro (rede,
# 429, 5xx) levanta TransientError, para o job tentar de novo; o resto, Error.
class Finture::TranscriptionClient
  class Error < StandardError; end
  class TransientError < Error; end

  DEFAULT_MODEL = 'gpt-4o-mini-transcribe'.freeze
  DEFAULT_API_VERSION = '2025-03-01-preview'.freeze
  DEFAULT_OPENAI_ENDPOINT = 'https://api.openai.com/v1'.freeze
  TIMEOUT = 60
  # Nomes que o motor erra sem ajuda (marcas, produtos, termos de seguro).
  DEFAULT_PROMPT = 'Atendimento da Criteria Seguros e da Finture pelo WhatsApp. Termos comuns: consórcio, Embracon, ' \
                   'financiamento imobiliário, home equity, seguro de vida, seguro de vida em grupo, plano de saúde, ' \
                   'corporate, seguros elementares, apólice, sinistro, boleto, corretora, assessor.'.freeze

  def self.configured?
    ENV.fetch('FINTURE_TRANSCRIPTION_API_KEY', '').present?
  end

  def self.prompt
    ENV.fetch('FINTURE_TRANSCRIPTION_PROMPT', '').presence || DEFAULT_PROMPT
  end

  def engine
    "#{provider}:#{model}"
  end

  def transcribe(path:, filename:, content_type:)
    response = post(path, filename, content_type, logprobs: logprobs?)
    # Versão da API sem suporte a logprobs: tenta de novo sem pedir a confiança.
    response = post(path, filename, content_type, logprobs: false) if response.status == 400 && logprobs?
    handle(response)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise TransientError, "#{e.class}: #{e.message}"
  end

  private

  def post(path, filename, content_type, logprobs:)
    File.open(path, 'rb') do |io|
      connection.post(url) do |req|
        req.headers.merge!(auth_headers)
        req.body = form(io, filename, content_type, logprobs)
      end
    end
  end

  def form(io, filename, content_type, logprobs)
    body = {
      file: Faraday::Multipart::FilePart.new(io, content_type.presence || 'application/octet-stream', filename),
      language: 'pt',
      prompt: self.class.prompt,
      response_format: 'json',
      # 0 reduz a "invenção" de texto em trechos de silêncio.
      temperature: '0'
    }
    body[:model] = model if provider == 'openai'
    body['include[]'] = 'logprobs' if logprobs
    body
  end

  def handle(response)
    status = response.status
    raise TransientError, "HTTP #{status}" if status == 429 || status >= 500
    raise Error, "HTTP #{status}: #{response.body.to_s.truncate(300)}" unless status.between?(200, 299)

    data = JSON.parse(response.body.to_s)
    { text: data['text'].to_s.strip, confidence: confidence(data['logprobs']), engine: engine }
  rescue JSON::ParserError => e
    raise Error, "resposta inválida: #{e.message}"
  end

  # Média da probabilidade de cada token (exp(logprob)). Sem logprobs => nil.
  def confidence(logprobs)
    values = Array(logprobs).filter_map { |lp| lp.is_a?(Hash) ? lp['logprob'] : nil }.map(&:to_f)
    return if values.empty?

    (values.sum { |v| Math.exp(v) } / values.size).round(3)
  end

  def connection
    Faraday.new do |f|
      f.request :multipart
      f.options.timeout = TIMEOUT
      f.options.open_timeout = 10
    end
  end

  def url
    return "#{endpoint}/audio/transcriptions" if provider == 'openai'

    "#{endpoint}/openai/deployments/#{model}/audio/transcriptions?api-version=#{api_version}"
  end

  def auth_headers
    provider == 'openai' ? { 'Authorization' => "Bearer #{api_key}" } : { 'api-key' => api_key }
  end

  def provider
    ENV.fetch('FINTURE_TRANSCRIPTION_PROVIDER', 'azure').to_s.downcase == 'openai' ? 'openai' : 'azure'
  end

  def endpoint
    value = ENV.fetch('FINTURE_TRANSCRIPTION_ENDPOINT', '').presence
    value ||= DEFAULT_OPENAI_ENDPOINT if provider == 'openai'
    raise Error, 'FINTURE_TRANSCRIPTION_ENDPOINT não configurado' if value.blank?

    value.chomp('/')
  end

  def model
    ENV.fetch('FINTURE_TRANSCRIPTION_MODEL', '').presence || DEFAULT_MODEL
  end

  def api_version
    ENV.fetch('FINTURE_TRANSCRIPTION_API_VERSION', '').presence || DEFAULT_API_VERSION
  end

  def api_key
    ENV.fetch('FINTURE_TRANSCRIPTION_API_KEY', '')
  end

  def logprobs?
    ENV.fetch('FINTURE_TRANSCRIPTION_LOGPROBS', 'true').to_s.downcase != 'false'
  end
end
