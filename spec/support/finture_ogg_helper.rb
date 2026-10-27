# Monta um Ogg/Opus mínimo (só os cabeçalhos das páginas) com a duração pedida,
# para testar a transcrição de áudio sem arquivo de verdade.
module FintureOggHelper
  PRE_SKIP = 312

  def ogg_opus_bytes(seconds:, filler: 2_000)
    head = ogg_page(0, "OpusHead\x01\x01".b + [PRE_SKIP].pack('v') + [48_000].pack('V') + "\x00\x00\x00".b)
    body = ogg_page(960, 'x'.b * filler)
    tail = ogg_page((seconds * 48_000).to_i + PRE_SKIP, 'y'.b * 50)
    head + body + tail
  end

  def ogg_page(granule, payload)
    'OggS'.b + "\x00\x00".b + [granule].pack('q<') + [1, 0, 0].pack('VVV') + [1, payload.bytesize.clamp(0, 255)].pack('CC') + payload
  end
end

RSpec.configure do |config|
  config.include FintureOggHelper
end
