require 'rails_helper'

RSpec.describe Finture::HubClient do
  let(:url) { 'https://hub.test/api/v1/demandas/ingest' }
  let(:env) { { 'FINTURE_HUB_BASE_URL' => 'https://hub.test/', 'FINTURE_HUB_INGEST_SECRET' => 'segredo' } }

  around { |example| with_modified_env(env) { example.run } }

  describe '.configured?' do
    it 'exige as duas variáveis' do
      expect(described_class).to be_configured
      with_modified_env('FINTURE_HUB_INGEST_SECRET' => '') { expect(described_class).not_to be_configured }
      with_modified_env('FINTURE_HUB_BASE_URL' => nil) { expect(described_class).not_to be_configured }
    end
  end

  describe '#upsert_demanda' do
    it 'envia JSON com o segredo no cabeçalho e devolve o corpo' do
      stub_request(:post, url).to_return(status: 201, body: { demanda: { id: 'abc' }, criada: true }.to_json,
                                         headers: { 'Content-Type' => 'application/json' })

      body = described_class.new.upsert_demanda({ external_id: 'chatwoot:1:2' })

      expect(body).to include('criada' => true)
      expect(WebMock).to(have_requested(:post, url).with do |req|
        req.headers['X-Ingest-Secret'] == 'segredo' && JSON.parse(req.body)['external_id'] == 'chatwoot:1:2'
      end)
    end

    it 'trata 429, 5xx e falha de rede como erro passageiro' do
      stub_request(:post, url).to_return(status: 503, body: '{"detail":{"code":"not_configured"}}')
      expect { described_class.new.upsert_demanda({}) }.to raise_error(described_class::TransientError, /503/)

      stub_request(:post, url).to_return(status: 429)
      expect { described_class.new.upsert_demanda({}) }.to raise_error(described_class::TransientError)

      stub_request(:post, url).to_timeout
      expect { described_class.new.upsert_demanda({}) }.to raise_error(described_class::TransientError)
    end

    it 'trata 4xx como erro definitivo' do
      stub_request(:post, url).to_return(status: 401, body: '{"detail":{"code":"invalid_secret"}}')
      expect { described_class.new.upsert_demanda({}) }.to raise_error(described_class::Error, /401/) do |error|
        expect(error).not_to be_a(described_class::TransientError)
      end
    end

    it 'falha cedo sem configuração' do
      with_modified_env('FINTURE_HUB_BASE_URL' => '') do
        expect { described_class.new.upsert_demanda({}) }.to raise_error(described_class::Error, /não configurados/)
      end
    end
  end
end
