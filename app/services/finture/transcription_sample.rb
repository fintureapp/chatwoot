# Avalia o motor de transcrição numa amostra de áudios (critério de aceite do
# card: qualidade, custo e tempo). Para cada áudio da pasta, transcreve com o
# mesmo cliente da produção e, se houver um <áudio>.txt ao lado com o texto
# esperado, mede a taxa de erro de palavras (WER) e os termos-chave acertados.
# Grava um CSV por áudio e devolve o resumo. Uso: rake finture:transcription:sample[pasta].
class Finture::TranscriptionSample
  EXTENSIONS = %w[ogg oga opus mp3 m4a wav webm mp4 mpeg].freeze
  KEY_TERMS = %w[consorcio embracon financiamento imobiliario equity vida grupo saude corporate elementares
                 apolice sinistro boleto criteria finture].freeze
  CSV_HEADERS = %w[arquivo segundos latencia_ms confianca status wer termos_esperados termos_acertados transcricao].freeze

  def initialize(dir:, out: nil, usd_per_minute: nil)
    @dir = dir
    @out = out || File.join(dir, "transcricao_amostra_#{Time.current.strftime('%Y%m%d_%H%M')}.csv")
    @usd_per_minute = (usd_per_minute || ENV.fetch('FINTURE_TRANSCRIPTION_USD_PER_MIN', 0.003)).to_f
    @client = Finture::TranscriptionClient.new
  end

  def run
    rows = files.map { |path| evaluate(path) }
    write_csv(rows)
    summary(rows)
  end

  private

  def files
    Dir.glob(File.join(@dir, '*')).select { |f| EXTENSIONS.include?(File.extname(f).delete('.').downcase) }.sort
  end

  def evaluate(path)
    seconds = Finture::OggDuration.seconds(path)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @client.transcribe(path: path, filename: File.basename(path), content_type: Marcel::MimeType.for(Pathname.new(path)))
    latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    row(path, seconds, latency, result)
  rescue Finture::TranscriptionClient::Error => e
    { 'arquivo' => File.basename(path), 'segundos' => seconds, 'status' => "erro: #{e.message.truncate(120)}" }
  end

  def row(path, seconds, latency, result)
    text = result[:text].to_s
    reference = reference_for(path)
    expected, hit = key_terms(reference, text)
    { 'arquivo' => File.basename(path), 'segundos' => seconds, 'latencia_ms' => latency, 'confianca' => result[:confidence],
      'status' => 'ok', 'wer' => reference && wer(reference, text), 'termos_esperados' => expected, 'termos_acertados' => hit,
      'transcricao' => text }
  end

  def reference_for(path)
    txt = path.sub(/\.[^.]+\z/, '.txt')
    File.exist?(txt) ? File.read(txt, encoding: 'UTF-8') : nil
  end

  def words(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9 ]/, ' ').split
  end

  # Distância de edição entre as listas de palavras / palavras esperadas.
  def wer(reference, hypothesis)
    ref = words(reference)
    hyp = words(hypothesis)
    return if ref.empty?

    prev = (0..hyp.size).to_a
    ref.each_with_index do |r, i|
      cur = [i + 1]
      hyp.each_with_index { |h, j| cur << [prev[j + 1] + 1, cur[j] + 1, prev[j] + (r == h ? 0 : 1)].min }
      prev = cur
    end
    (prev.last.to_f / ref.size).round(3)
  end

  def key_terms(reference, hypothesis)
    return [nil, nil] if reference.nil?

    expected = words(reference) & KEY_TERMS
    [expected.size, (expected & words(hypothesis)).size]
  end

  def write_csv(rows)
    CSV.open(@out, 'w') do |csv|
      csv << CSV_HEADERS
      rows.each { |r| csv << CSV_HEADERS.map { |h| r[h] } }
    end
  end

  def summary(rows)
    ok = rows.select { |r| r['status'] == 'ok' }
    { arquivos: rows.size, com_erro: rows.size - ok.size }.merge(cost_summary(rows), quality_summary(ok), csv: @out)
  end

  # Duração só sai de Ogg/Opus (áudio de voz do WhatsApp); os outros formatos
  # ficam fora dos minutos e do custo e aparecem em sem_duracao.
  def cost_summary(rows)
    minutes = rows.sum { |r| r['segundos'].to_f } / 60.0
    { sem_duracao: rows.count { |r| r['segundos'].nil? }, minutos: minutes.round(2),
      custo_estimado_usd: (minutes * @usd_per_minute).round(4) }
  end

  def quality_summary(ok_rows)
    latencies = ok_rows.filter_map { |r| r['latencia_ms'] }.sort
    wers = ok_rows.filter_map { |r| r['wer'] }
    { latencia_p50_ms: percentile(latencies, 0.5), latencia_p95_ms: percentile(latencies, 0.95),
      wer_medio: wers.empty? ? nil : (wers.sum / wers.size).round(3),
      termos_acertados: "#{ok_rows.sum { |r| r['termos_acertados'].to_i }}/#{ok_rows.sum { |r| r['termos_esperados'].to_i }}" }
  end

  def percentile(sorted, pct)
    return if sorted.empty?

    sorted[[(sorted.size * pct).ceil - 1, 0].max]
  end
end
