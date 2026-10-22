# Transcreve UM áudio recebido do cliente para a triagem por IA (n8n) e para o
# atendente, que lê o texto embaixo do áudio. O áudio original não muda.
#
# Onde fica: no próprio anexo, junto do áudio (mesmo acesso e mesma retenção da
# mensagem; apagou a mensagem, apaga os dois).
#   meta['transcribed_text']       texto, só quando deu certo (o chip de áudio já mostra)
#   meta['finture_transcription']  situação e trilha: status, engine, confidence,
#                                  duration_seconds, bytes, latency_ms, transcribed_at, error
#
# status: processing (em andamento) | ok | unintelligible (motor devolveu nada,
# texto típico de silêncio ou confiança baixa) | too_long | failed (erro do motor).
# Ao terminar, emite message_updated: o webhook do bot (n8n) recebe o anexo com
# transcribed_text e transcription_status e segue a triagem como se fosse texto.
#
# Roda uma vez por anexo: a trava do anexo impede duas transcrições ao mesmo
# tempo e um status final nunca é refeito (evento repetido não duplica nada).
class Finture::AudioTranscriptionService
  META_KEY = 'finture_transcription'.freeze
  FINAL_STATUSES = %w[ok unintelligible too_long failed].freeze
  # "processing" mais velho que isso é tratado como abandonado (worker morto).
  PROCESSING_TTL = 10.minutes
  # Limite da API de transcrição (25 MB decimais).
  API_BYTE_LIMIT = 25_000_000
  MAX_TEXT = 5_000
  OGG_TYPES = %w[audio/ogg audio/opus application/ogg].freeze
  OGG_EXTENSIONS = %w[ogg oga opus].freeze
  # Frases que modelos da família Whisper "inventam" em áudio mudo ou com ruído.
  SILENCE_HALLUCINATIONS = [
    /amara\.org/i, /legendas? (pela|por|de) /i, /obrigad[oa] por assistir/i,
    /inscreva-se( no canal)?/i, /ative o sininho/i, /deixe (o )?seu like/i
  ].freeze

  attr_reader :attachment

  def initialize(attachment)
    @attachment = attachment
  end

  def perform
    return unless eligible?
    return unless claim!

    transcribe!
  rescue Finture::TranscriptionClient::TransientError, ActiveStorage::FileNotFoundError
    release!
    raise
  rescue Finture::TranscriptionClient::Error => e
    finish!('failed', 'error' => e.message.truncate(300))
  rescue StandardError => e
    # Erro inesperado depois da trava: fecha como failed para o n8n responder ao
    # cliente (senão o áudio ficaria "processing" e sem resposta).
    ChatwootExceptionTracker.new(e, account: attachment.account).capture_exception
    finish!('failed', 'error' => "#{e.class}: #{e.message}".truncate(300))
  end

  # Fim das novas tentativas do job (erro passageiro que não passou).
  def mark_failed!(error)
    return if FINAL_STATUSES.include?(info['status'])

    finish!('failed', 'error' => "#{error.class}: #{error.message}".truncate(300))
  end

  def eligible?
    message = attachment.message
    attachment.audio? && message&.incoming? &&
      Finture::InboxConfig.audio_transcription?(message.inbox_id) &&
      Finture::TranscriptionClient.configured?
  end

  private

  def transcribe!
    # Já transcrito por outro caminho (ex.: recurso do Captain): só registra.
    existing = attachment.meta&.[]('transcribed_text').to_s.strip
    return finish!('ok', 'engine' => 'existing', 'text' => existing) if existing.present?

    # Arquivo ainda subindo para o storage: o job tenta de novo.
    raise ActiveStorage::FileNotFoundError, "anexo #{attachment.id} sem arquivo" unless attachment.file.attached?

    blob = attachment.file.blob
    return finish!('too_long', 'bytes' => blob.byte_size) if blob.byte_size > max_bytes

    blob.open { |file| transcribe_file!(file, blob) }
  end

  def transcribe_file!(file, blob)
    trail = { 'bytes' => blob.byte_size, 'duration_seconds' => (Finture::OggDuration.seconds(file.path) if ogg?(blob)) }.compact
    return finish!('too_long', trail) if trail['duration_seconds'].to_f > max_seconds

    result, latency_ms = timed { call_engine(file, blob) }
    trail.merge!('latency_ms' => latency_ms, 'engine' => result[:engine], 'confidence' => result[:confidence]).compact!

    text = result[:text].to_s.strip.truncate(MAX_TEXT)
    status = assess(text, result[:confidence])
    finish!(status, trail.merge(text_entry(status, text)))
  end

  def call_engine(file, blob)
    client.transcribe(path: file.path, filename: filename_for(blob), content_type: blob.content_type)
  end

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    [yield, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round]
  end

  # Texto aproveitado vai para transcribed_text; o descartado fica só na trilha.
  def text_entry(status, text)
    return { 'text' => text } if status == 'ok'

    text.present? ? { 'discarded_text' => text } : {}
  end

  # Texto que não serve para a IA seguir: vazio, só ruído, frase típica de
  # silêncio, eco do vocabulário de apoio ou confiança abaixo do mínimo.
  def assess(text, confidence)
    return 'unintelligible' if text.scan(/\p{L}/).size < 2
    return 'unintelligible' if SILENCE_HALLUCINATIONS.any? { |re| text.match?(re) }
    return 'unintelligible' if prompt_echo?(text)
    return 'unintelligible' if confidence && confidence < min_confidence

    'ok'
  end

  def prompt_echo?(text)
    normalized = normalize(text)
    normalized.length > 40 && normalize(Finture::TranscriptionClient.prompt).include?(normalized)
  end

  def normalize(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9 ]/, ' ').squish
  end

  # Trava o anexo e marca "processing". false = outro job já está nele ou já terminou.
  def claim!
    claimed = false
    attachment.with_lock do
      current = info
      next if FINAL_STATUSES.include?(current['status'])
      next if current['status'] == 'processing' && !stale?(current)

      write!(current.merge('status' => 'processing', 'started_at' => Time.current.iso8601))
      claimed = true
    end
    claimed
  end

  # Erro passageiro: libera a trava para a próxima tentativa do job.
  def release!
    attachment.with_lock do
      write!(info.except('status', 'started_at')) if info['status'] == 'processing'
    end
  end

  def finish!(status, extras = {})
    text = extras.delete('text')
    attachment.with_lock do
      meta = (attachment.meta || {}).dup
      meta['transcribed_text'] = text if status == 'ok'
      meta[META_KEY] = info.except('started_at', 'error', 'discarded_text')
                           .merge(extras.stringify_keys)
                           .merge('status' => status, 'source' => 'auto', 'transcribed_at' => Time.current.iso8601)
      attachment.update!(meta: meta)
    end
    attachment.message.reload.send_update_event
    status
  end

  def write!(value)
    attachment.update!(meta: (attachment.meta || {}).merge(META_KEY => value))
  end

  def info
    (attachment.meta || {})[META_KEY].is_a?(Hash) ? attachment.meta[META_KEY] : {}
  end

  def stale?(current)
    started = Time.zone.parse(current['started_at'].to_s)
    started.nil? || started < PROCESSING_TTL.ago
  rescue ArgumentError
    true
  end

  def ogg?(blob)
    OGG_TYPES.include?(blob.content_type.to_s.split(';').first) ||
      OGG_EXTENSIONS.include?(blob.filename.extension_without_delimiter.to_s.downcase)
  end

  # A API descobre o formato pela extensão do nome: garante uma.
  def filename_for(blob)
    name = blob.filename.to_s.presence || 'audio'
    return name if blob.filename.extension_without_delimiter.present?

    subtype = blob.content_type.to_s.split(';').first.to_s.split('/').last.to_s
    ext = { 'x-m4a' => 'm4a', 'mp4' => 'm4a', 'x-wav' => 'wav', 'mpeg' => 'mp3', 'x-mp3' => 'mp3', 'opus' => 'ogg' }.fetch(subtype, subtype)
    ext.present? ? "#{name}.#{ext}" : name
  end

  def client
    @client ||= Finture::TranscriptionClient.new
  end

  def max_bytes
    [ENV.fetch('FINTURE_TRANSCRIPTION_MAX_BYTES', 10_000_000).to_i, API_BYTE_LIMIT].min
  end

  def max_seconds
    ENV.fetch('FINTURE_TRANSCRIPTION_MAX_SECONDS', 180).to_i
  end

  def min_confidence
    ENV.fetch('FINTURE_TRANSCRIPTION_MIN_CONFIDENCE', 0.5).to_f
  end
end
