require 'rails_helper'

RSpec.describe Finture::OggDuration do
  def with_file(bytes)
    file = Tempfile.new(['voz', '.ogg'], binmode: true)
    file.write(bytes)
    file.flush
    yield file.path
  ensure
    file&.close!
  end

  it 'lê a duração de um Ogg/Opus descontando o pre-skip' do
    with_file(ogg_opus_bytes(seconds: 42)) { |path| expect(described_class.seconds(path)).to eq(42.0) }
  end

  it 'acha a última página mesmo com áudio maior que o trecho lido' do
    with_file(ogg_opus_bytes(seconds: 200, filler: 100_000)) { |path| expect(described_class.seconds(path)).to eq(200.0) }
  end

  it 'devolve nil para arquivo que não é Ogg' do
    with_file("ID3\x03\x00 mp3 qualquer".b) { |path| expect(described_class.seconds(path)).to be_nil }
  end

  it 'devolve nil para arquivo inexistente' do
    expect(described_class.seconds('/nao/existe.ogg')).to be_nil
  end
end
