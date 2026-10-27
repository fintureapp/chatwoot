# Duração de um arquivo Ogg (áudio de voz do WhatsApp é Ogg/Opus) sem ffprobe,
# que não existe no container. Lê só o fim do arquivo: a última página Ogg traz
# a posição do último quadro (granule position); em Opus ela conta amostras a
# 48 kHz, descontado o pre-skip do cabeçalho OpusHead. Formato fora disso ou
# arquivo corrompido => nil (quem chama decide pelo tamanho).
class Finture::OggDuration
  CAPTURE = 'OggS'.b.freeze
  OPUS_HEAD = 'OpusHead'.b.freeze
  VORBIS_HEAD = "\x01vorbis".b.freeze
  TAIL_BYTES = 65_536
  HEAD_BYTES = 512

  def self.seconds(path)
    new(path).seconds
  end

  def initialize(path)
    @path = path
  end

  def seconds
    head = read(0, HEAD_BYTES)
    return unless head&.start_with?(CAPTURE)

    rate, pre_skip = sample_rate(head)
    granule = last_granule
    return if rate.nil? || granule.nil? || granule.negative?

    ([granule - pre_skip, 0].max / rate.to_f).round(2)
  rescue SystemCallError, IOError
    nil
  end

  private

  # Opus: sempre 48 kHz para a granule position; pre-skip em OpusHead[10..11].
  # Vorbis: taxa em "\x01vorbis"[12..15].
  def sample_rate(head)
    if (i = head.index(OPUS_HEAD))
      [48_000, head.byteslice(i + 10, 2).to_s.unpack1('v').to_i]
    elsif (i = head.index(VORBIS_HEAD))
      rate = head.byteslice(i + 12, 4).to_s.unpack1('V').to_i
      [rate.positive? ? rate : nil, 0]
    end
  end

  # Granule position (int64 little-endian, bytes 6..13) da última página. Confere
  # a versão (byte 4 = 0) para não confundir "OggS" que apareça dentro do áudio.
  def last_granule
    tail = read([File.size(@path) - TAIL_BYTES, 0].max, TAIL_BYTES).to_s
    i = tail.bytesize
    while (i = tail.rindex(CAPTURE, i - 1))
      return tail.byteslice(i + 6, 8).unpack1('q<') if tail.bytesize >= i + 14 && tail.getbyte(i + 4).zero?
      return if i.zero?
    end
  end

  def read(offset, length)
    File.open(@path, 'rb') do |f|
      f.seek(offset)
      f.read(length)
    end
  end
end
