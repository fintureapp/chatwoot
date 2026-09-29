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

  # As etapas de espera do cliente não entram no "Tempo médio na etapa" do
  # Dashboard Operacional — lá o relógio corre por conta do lead, não do time.
  describe 'counts_in_stage_time' do
    def counts_by_slug
      described_class.where(inbox_id: inbox.id).pluck(:slug, :counts_in_stage_time).to_h
    end

    it 'seeds the operational waiting stages switched off' do
      described_class.seed_defaults!(inbox, 'operacional')

      expect(counts_by_slug).to eq('chamada_iniciada' => false, 'em_triagem' => false, 'em_atendimento' => true)
    end

    it 'seeds every commercial stage switched on' do
      described_class.seed_defaults!(inbox, 'comercial')

      expect(counts_by_slug.values).to all(be(true))
    end

    it 'defaults a stage created by hand to counting' do
      stage = described_class.create!(account: account, inbox: inbox, slug: 'aguardando_cliente',
                                      name: 'Aguardando cliente', color: 'amber', position: 1)

      expect(stage.counts_in_stage_time).to be(true)
    end

    it 'follows the locked stage across a classification switch' do
      described_class.seed_defaults!(inbox, 'comercial')
      locked = described_class.find_by(inbox_id: inbox.id, locked: true)

      described_class.ensure_stages_for_type!(inbox, 'operacional')
      expect(locked.reload.counts_in_stage_time).to be(false)

      described_class.ensure_stages_for_type!(inbox, 'comercial')
      expect(locked.reload.counts_in_stage_time).to be(true)
    end
  end
end
