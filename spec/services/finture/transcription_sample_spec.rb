require 'rails_helper'

RSpec.describe Finture::TranscriptionSample do
  let(:url) { 'https://finture.openai.azure.com/openai/deployments/gpt-4o-mini-transcribe/audio/transcriptions?api-version=2025-03-01-preview' }

  let(:dir) { Dir.mktmpdir }

  around do |example|
    with_modified_env('FINTURE_TRANSCRIPTION_API_KEY' => 'chave', 'FINTURE_TRANSCRIPTION_ENDPOINT' => 'https://finture.openai.azure.com') do
      example.run
    end
  end

  after { FileUtils.remove_entry(dir) }

  it 'mede erro de palavras, termos-chave, duração e custo' do
    File.binwrite(File.join(dir, 'a.ogg'), ogg_opus_bytes(seconds: 30))
    File.write(File.join(dir, 'a.txt'), 'Quero falar sobre o consórcio da Embracon')
    File.binwrite(File.join(dir, 'b.ogg'), ogg_opus_bytes(seconds: 30))
    stub_request(:post, url).to_return(
      { status: 200, body: { text: 'Quero falar sobre o consórcio da Embraco' }.to_json },
      { status: 401, body: 'sem acesso' }
    )

    summary = described_class.new(dir: dir, usd_per_minute: 0.006).run

    expect(summary).to include(arquivos: 2, com_erro: 1, minutos: 1.0, custo_estimado_usd: 0.006,
                               termos_acertados: '1/2')
    expect(summary[:wer_medio]).to eq(0.143)
    rows = CSV.read(summary[:csv], headers: true)
    expect(rows.first['transcricao']).to eq('Quero falar sobre o consórcio da Embraco')
    expect(rows[1]['status']).to start_with('erro: HTTP 401')
  end
end
