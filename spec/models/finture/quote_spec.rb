require 'rails_helper'

RSpec.describe Finture::Quote do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  def build_quote(attrs = {})
    described_class.new(
      { account: account, conversation: conversation, product_type: 'saude_pme' }.merge(attrs)
    )
  end

  it 'aceita produto e dados válidos' do
    quote = build_quote(data: { 'lives' => { '0-18' => 1, '59+' => 2 }, 'accommodation' => 'apartamento' })
    expect(quote).to be_valid
    expect(quote.lives_total).to eq(3)
  end

  it 'rejeita produto fora da lista' do
    expect(build_quote(product_type: 'previdencia')).not_to be_valid
  end

  it 'rejeita faixa etária fora do padrão ANS' do
    quote = build_quote(data: { 'lives' => { '0-17' => 1 } })
    expect(quote).not_to be_valid
    expect(quote.errors[:data]).to be_present
  end

  it 'rejeita acomodação inválida' do
    expect(build_quote(data: { 'accommodation' => 'suite' })).not_to be_valid
  end

  it 'não valida faixas ANS em outros produtos' do
    quote = build_quote(product_type: 'consorcio', data: { 'asset_type' => 'imovel' })
    expect(quote).to be_valid
  end

  it 'permite uma única cotação por conversa' do
    build_quote.save!
    expect(build_quote(product_type: 'seguros')).not_to be_valid
  end
end
