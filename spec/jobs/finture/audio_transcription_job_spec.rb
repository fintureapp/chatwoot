require 'rails_helper'

RSpec.describe Finture::AudioTranscriptionJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { 'https://finture.openai.azure.com/openai/deployments/gpt-4o-mini-transcribe/audio/transcriptions?api-version=2025-03-01-preview' }

  def message_of(type)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type, content: nil)
  end

  def attach(message, file_type: :audio)
    message.attachments.create!(
      account_id: account.id, file_type: file_type,
      file: { io: StringIO.new(ogg_opus_bytes(seconds: 8)), filename: 'voz.ogg', content_type: 'audio/ogg' }
    )
  end

  describe 'enfileiramento' do
    it 'enfileira para áudio recebido do cliente' do
      expect { attach(message_of(:incoming)) }.to have_enqueued_job(described_class)
    end

    it 'não enfileira para áudio do atendente nem para imagem' do
      expect { attach(message_of(:outgoing)) }.not_to have_enqueued_job(described_class)
      expect { attach(message_of(:incoming), file_type: :image) }.not_to have_enqueued_job(described_class)
    end
  end

  describe '#perform' do
    around do |example|
      with_modified_env('FINTURE_TRANSCRIPTION_API_KEY' => 'chave', 'FINTURE_TRANSCRIPTION_ENDPOINT' => 'https://finture.openai.azure.com') do
        example.run
      end
    end

    before { Finture::InboxConfig.create!(account: account, inbox: inbox, ai_enabled: true) }

    it 'marca failed quando o motor segue fora do ar depois das novas tentativas' do
      stub_request(:post, url).to_return(status: 503, body: 'indisponivel')
      attachment = attach(message_of(:incoming))

      perform_enqueued_jobs { described_class.perform_later(attachment.id) }

      expect(attachment.reload.meta.dig('finture_transcription', 'status')).to eq('failed')
      expect(WebMock).to have_requested(:post, url).times(3)
    end

    it 'ignora anexo apagado' do
      expect { described_class.perform_now(0) }.not_to raise_error
    end
  end
end
