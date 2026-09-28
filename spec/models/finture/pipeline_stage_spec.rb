require 'rails_helper'

RSpec.describe Finture::PipelineStage do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def slugs
    described_class.where(inbox_id: inbox.id).ordered.pluck(:slug)
  end

  describe '.ensure_stages_for_type!' do
    context 'when the inbox has no stages yet' do
      it 'seeds the full funnel of the given type' do
        described_class.ensure_stages_for_type!(inbox, 'operacional')

        expect(slugs).to eq(%w[chamada_iniciada em_triagem em_atendimento])
        expect(described_class.find_by(inbox_id: inbox.id, slug: 'chamada_iniciada')).to be_locked
      end
    end

    context 'when the inbox already has a commercial funnel with custom columns' do
      before do
        described_class.seed_defaults!(inbox, 'comercial')
        described_class.create!(account: account, inbox: inbox, slug: 'aguardando_cliente',
                                name: 'Aguardando cliente', color: 'amber', position: 3, locked: false)
      end

      it 'renames the locked stage, adds the missing operational stages right after it and keeps the rest' do
        described_class.ensure_stages_for_type!(inbox, 'operacional')

        locked = described_class.find_by(inbox_id: inbox.id, locked: true)
        expect(locked.slug).to eq('lead_identificado')
        expect(locked.name).to eq('Chamada Iniciada')
        expect(locked.position).to eq(0)
        expect(slugs).to eq(%w[lead_identificado em_triagem em_atendimento primeiro_contato proposta_enviada aguardando_cliente])
        expect(described_class.where(inbox_id: inbox.id).ordered.pluck(:position)).to eq((0..5).to_a)
      end

      it 'is idempotent' do
        2.times { described_class.ensure_stages_for_type!(inbox, 'operacional') }

        expect(slugs).to eq(%w[lead_identificado em_triagem em_atendimento primeiro_contato proposta_enviada aguardando_cliente])
      end

      it 'restores the commercial label when switching back' do
        described_class.ensure_stages_for_type!(inbox, 'operacional')
        described_class.ensure_stages_for_type!(inbox, 'comercial')

        expect(described_class.find_by(inbox_id: inbox.id, locked: true).name).to eq('Lead Identificado')
        expect(slugs).to include('em_triagem', 'primeiro_contato')
      end
    end
  end
end
