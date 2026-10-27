require 'rails_helper'

RSpec.describe Finture::AudioTranscriptionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil) }
  let(:url) { 'https://finture.openai.azure.com/openai/deployments/transcrever/audio/transcriptions?api-version=2025-03-01-preview' }
  let(:env) do
    { 'FINTURE_TRANSCRIPTION_API_KEY' => 'chave-teste', 'FINTURE_TRANSCRIPTION_ENDPOINT' => 'https://finture.openai.azure.com/',
      'FINTURE_TRANSCRIPTION_MODEL' => 'transcrever' }
  end

  around { |example| with_modified_env(env) { example.run } }

  before { Finture::InboxConfig.create!(account: account, inbox: inbox, ai_enabled: true) }

  def audio_attachment(seconds: 12, owner: message, filename: 'voz.ogg', content_type: 'audio/ogg')
    owner.attachments.create!(
      account_id: account.id, file_type: :audio,
      file: { io: StringIO.new(ogg_opus_bytes(seconds: seconds)), filename: filename, content_type: content_type }
    )
  end

  def stub_engine(text:, logprob: -0.05, status: 200)
    body = { text: text, logprobs: [{ token: 'a', logprob: logprob, bytes: [97] }] }.to_json
    stub_request(:post, url).to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def info(attachment)
    attachment.reload.meta['finture_transcription']
  end

  describe '#perform' do
    it 'grava a transcrição no anexo e avisa o bot com message_updated' do
      stub_engine(text: 'Oi, quero falar sobre o meu consórcio da Embracon.')
      attachment = audio_attachment
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      expect(described_class.new(attachment).perform).to eq('ok')

      attachment.reload
      expect(attachment.meta['transcribed_text']).to eq('Oi, quero falar sobre o meu consórcio da Embracon.')
      expect(info(attachment)).to include('status' => 'ok', 'engine' => 'azure:transcrever', 'duration_seconds' => 12.0,
                                          'confidence' => 0.951, 'source' => 'auto')
      expect(attachment.push_event_data).to include(transcribed_text: 'Oi, quero falar sobre o meu consórcio da Embracon.',
                                                    transcription_status: 'ok')
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::MESSAGE_UPDATED, anything, hash_including(message: message))
      expect(WebMock).to(have_requested(:post, url).with do |req|
        req.headers['Api-Key'] == 'chave-teste' && req.body.include?('name="language"') && req.body.include?('logprobs')
      end)
    end

    it 'não transcreve de novo quando o evento se repete' do
      stub_engine(text: 'Quero cotar um seguro de vida.')
      attachment = audio_attachment

      described_class.new(attachment).perform
      expect(described_class.new(attachment.reload).perform).to be_nil

      expect(WebMock).to have_requested(:post, url).once
    end

    it 'ignora caixa sem IA e sem transcrição ligada' do
      Finture::InboxConfig.find_by(inbox_id: inbox.id).update!(ai_enabled: false)
      attachment = audio_attachment

      expect(described_class.new(attachment).perform).to be_nil
      expect(info(attachment)).to be_nil
      expect(WebMock).not_to have_requested(:post, url)
    end

    it 'transcreve em caixa sem IA quando a transcrição está ligada' do
      Finture::InboxConfig.find_by(inbox_id: inbox.id).update!(ai_enabled: false, audio_transcription_enabled: true)
      stub_engine(text: 'Preciso da segunda via do boleto.')

      expect(described_class.new(audio_attachment).perform).to eq('ok')
    end

    it 'ignora áudio enviado pelo atendente' do
      outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)

      expect(described_class.new(audio_attachment(owner: outgoing)).perform).to be_nil
    end

    it 'fica desligada sem chave da API' do
      env['FINTURE_TRANSCRIPTION_API_KEY'] = ''
      with_modified_env(env) do
        expect(described_class.new(audio_attachment).perform).to be_nil
      end
    end

    it 'marca too_long sem chamar o motor quando passa da duração máxima' do
      attachment = audio_attachment(seconds: 400)

      expect(described_class.new(attachment).perform).to eq('too_long')
      expect(info(attachment)).to include('status' => 'too_long', 'duration_seconds' => 400.0)
      expect(attachment.reload.meta['transcribed_text']).to be_nil
      expect(WebMock).not_to have_requested(:post, url)
    end

    it 'descarta o texto típico de silêncio' do
      stub_engine(text: 'Legendas pela comunidade Amara.org')
      attachment = audio_attachment

      expect(described_class.new(attachment).perform).to eq('unintelligible')
      expect(attachment.reload.meta['transcribed_text']).to be_nil
      expect(info(attachment)['discarded_text']).to eq('Legendas pela comunidade Amara.org')
      expect(attachment.push_event_data[:transcription_status]).to eq('unintelligible')
    end

    it 'descarta transcrição com confiança baixa' do
      stub_engine(text: 'quero o negócio lá do coiso', logprob: -2.5)

      expect(described_class.new(audio_attachment).perform).to eq('unintelligible')
    end

    it 'aceita transcrição curta e clara' do
      stub_engine(text: 'Consórcio.')

      expect(described_class.new(audio_attachment).perform).to eq('ok')
    end

    it 'marca failed quando o motor recusa (ex.: chave inválida)' do
      stub_request(:post, url).to_return(status: 401, body: '{"error":"unauthorized"}')
      attachment = audio_attachment

      expect(described_class.new(attachment).perform).to eq('failed')
      expect(info(attachment)['error']).to include('HTTP 401')
    end

    it 'libera o anexo para nova tentativa em erro passageiro' do
      stub_request(:post, url).to_return(status: 503, body: 'indisponivel')
      attachment = audio_attachment

      expect { described_class.new(attachment).perform }.to raise_error(Finture::TranscriptionClient::TransientError)
      expect(info(attachment)).to eq({})
    end

    it 'fecha como failed em erro inesperado, para o bot não ficar mudo' do
      attachment = audio_attachment
      allow(Finture::OggDuration).to receive(:seconds).and_raise(NoMethodError, 'quebrou')

      expect(described_class.new(attachment).perform).to eq('failed')
      expect(info(attachment)['error']).to include('NoMethodError')
    end

    it 'tenta sem logprobs quando a versão da API não aceita' do
      stub_request(:post, url).to_return(
        { status: 400, body: '{"error":"include not supported"}' },
        { status: 200, body: { text: 'Quero falar com um atendente.' }.to_json }
      )
      attachment = audio_attachment

      expect(described_class.new(attachment).perform).to eq('ok')
      expect(info(attachment)).not_to have_key('confidence')
      expect(WebMock).to have_requested(:post, url).twice
    end

    it 'usa a OpenAI direto quando configurado' do
      openai_url = 'https://api.openai.com/v1/audio/transcriptions'
      stub_request(:post, openai_url).to_return(status: 200, body: { text: 'Bom dia, sobre o plano de saúde.' }.to_json)
      with_modified_env(env.merge('FINTURE_TRANSCRIPTION_PROVIDER' => 'openai', 'FINTURE_TRANSCRIPTION_ENDPOINT' => '',
                                  'FINTURE_TRANSCRIPTION_MODEL' => '')) do
        expect(described_class.new(audio_attachment).perform).to eq('ok')
      end
      expect(WebMock).to(have_requested(:post, openai_url).with do |req|
        req.headers['Authorization'] == 'Bearer chave-teste' && req.body.include?('gpt-4o-mini-transcribe')
      end)
    end

    it 'aproveita transcrição que já existe no anexo' do
      attachment = audio_attachment
      attachment.update!(meta: { 'transcribed_text' => 'Texto já transcrito.' })

      expect(described_class.new(attachment).perform).to eq('ok')
      expect(info(attachment)).to include('status' => 'ok', 'engine' => 'existing')
      expect(WebMock).not_to have_requested(:post, url)
    end
  end

  describe '#mark_failed!' do
    it 'marca failed quando as tentativas acabam' do
      attachment = audio_attachment

      described_class.new(attachment).mark_failed!(Finture::TranscriptionClient::TransientError.new('HTTP 503'))

      expect(info(attachment)).to include('status' => 'failed')
      expect(attachment.push_event_data[:transcription_status]).to eq('failed')
    end

    it 'não troca um status final' do
      stub_engine(text: 'Quero cancelar a apólice.')
      attachment = audio_attachment
      described_class.new(attachment).perform

      described_class.new(attachment.reload).mark_failed!(StandardError.new('atrasado'))

      expect(info(attachment)['status']).to eq('ok')
    end
  end
end
