require 'rails_helper'

RSpec.describe Finture::QuoteUpsertService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  def perform(params:, source:, temperature: nil)
    described_class.new(
      conversation: conversation,
      params: params,
      source: source,
      temperature: temperature
    ).perform
  end

  describe 'source agent (aba Cotação)' do
    it 'cria a cotação e espelha o resumo na conversa' do
      quote = perform(
        params: { product_type: 'saude_pme', data: { 'lives' => { '0-18' => 2 } }, total_value: 1850 },
        source: 'agent'
      )
      expect(quote).to be_persisted
      expect(conversation.reload.custom_attributes['sdr_quote_summary']).to include('Saúde PME')
      expect(conversation.custom_attributes['sdr_quote_summary']).to include('2 vidas')
    end

    it 'sobrescreve dados existentes (edição humana manda)' do
      perform(params: { product_type: 'saude_pme', data: { 'city' => 'Campinas' } }, source: 'agent')
      perform(params: { data: { 'city' => 'São Paulo' } }, source: 'agent')
      expect(Finture::Quote.last.data['city']).to eq('São Paulo')
    end

    it 'sugere valor_potencial apenas quando vazio (sugerir sem amarrar)' do
      perform(params: { product_type: 'credito', total_value: 50_000 }, source: 'agent')
      expect(conversation.reload.custom_attributes['valor_potencial']).to eq(50_000.0)

      perform(params: { total_value: 80_000 }, source: 'agent')
      expect(conversation.reload.custom_attributes['valor_potencial']).to eq(50_000.0)
    end
  end

  describe 'source n8n (SDR IA)' do
    it 'só preenche campos vazios — nunca desfaz edição humana' do
      perform(params: { product_type: 'saude_pme', data: { 'city' => 'Campinas' } }, source: 'agent')
      perform(
        params: { data: { 'city' => 'Osasco', 'current_plan' => 'Amil' } },
        source: 'n8n'
      )
      quote = Finture::Quote.last
      expect(quote.data['city']).to eq('Campinas')
      expect(quote.data['current_plan']).to eq('Amil')
      expect(quote.source).to eq('n8n')
    end

    it 'não troca o product_type de cotação existente' do
      perform(params: { product_type: 'saude_pme' }, source: 'agent')
      perform(params: { product_type: 'credito' }, source: 'n8n')
      expect(Finture::Quote.last.product_type).to eq('saude_pme')
    end

    it 'temperatura vira prioridade só quando a conversa não tem prioridade' do
      perform(params: { product_type: 'saude_pme' }, source: 'n8n', temperature: 'morno')
      expect(conversation.reload.priority).to eq('medium')

      perform(params: {}, source: 'n8n', temperature: 'quente')
      expect(conversation.reload.priority).to eq('medium')
    end

    it 'não mexe na prioridade definida por humano' do
      conversation.update!(priority: 'urgent')
      perform(params: { product_type: 'saude_pme' }, source: 'n8n', temperature: 'frio')
      expect(conversation.reload.priority).to eq('urgent')
    end
  end
end
