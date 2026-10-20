require 'rails_helper'

describe Conversations::FilterService do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:proposta) { create(:conversation, account: account, inbox: inbox, custom_attributes: { 'sdr_stage' => 'proposta_enviada' }) }
  let!(:contato) { create(:conversation, account: account, inbox: inbox, custom_attributes: { 'sdr_stage' => 'primeiro_contato' }) }
  let!(:sem_etapa) { create(:conversation, account: account, inbox: inbox, custom_attributes: {}) }

  def ids_for(payload)
    described_class.new({ payload: payload, page: 1 }.with_indifferent_access, admin, account)
                   .perform[:conversations].map(&:id)
  end

  it 'filtra pela coluna do Kanban (sdr_stage)' do
    ids = ids_for([{ attribute_key: 'sdr_stage', filter_operator: 'equal_to', values: ['proposta_enviada'] }])

    expect(ids).to contain_exactly(proposta.id)
  end

  it 'inclui as conversas sem etapa quando o valor vazio é enviado (1ª coluna)' do
    ids = ids_for([
                    { attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: 'AND' },
                    { attribute_key: 'sdr_stage', filter_operator: 'equal_to', values: ['primeiro_contato', ''] }
                  ])

    expect(ids).to contain_exactly(contato.id, sem_etapa.id)
  end
end
