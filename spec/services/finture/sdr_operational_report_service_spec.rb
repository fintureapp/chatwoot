require 'rails_helper'

# Visão Operacional do Dashboard SDR. Os casos abaixo travam os quatro erros de
# contagem reportados na caixa operacional: conversa já resolvida contando como
# lead aberto, KPIs ignorando o filtro de período, área sumindo do SLA por falta
# de amostra e etapa de espera do cliente entrando no tempo médio por etapa.
RSpec.describe Finture::SdrOperationalReportService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2026-09-29 12:00:00') }
  let(:since) { (now - 7.days).to_i }
  let(:until_at) { now.to_i }

  def report(scoped_inbox: inbox)
    described_class.new(account: account, current_user: nil, inbox_id: scoped_inbox&.id,
                        since: since, until_at: until_at).perform
  end

  def conversation(status: :open, created_at: now - 2.days, last_activity_at: nil, **attrs)
    conv = create(:conversation, account: account, inbox: inbox, status: status, **attrs)
    conv.update_columns(created_at: created_at, last_activity_at: last_activity_at || created_at) # rubocop:disable Rails/SkipsModelValidations
    conv.reload
  end

  around { |example| travel_to(now) { example.run } }

  describe 'leads sem responsável e leads parados' do
    context 'when the inbox is operational' do
      before { Finture::InboxConfig.create!(account: account, inbox: inbox, kanban_type: 'operacional') }

      it 'ignores resolved conversations — na caixa operacional a demanda sai do board ao resolver' do
        Finture::PipelineStage.seed_defaults!(inbox, 'operacional')
        conversation(status: :resolved, assignee: nil)
        conversation(status: :open, assignee: nil)

        result = report

        expect(result[:kpis][:unassigned]).to eq(1)
        expect(result[:load].sum { |row| row[:count] }).to eq(1)
      end

      it 'keeps resolved conversations out of "leads parados"' do
        conversation(status: :resolved, created_at: now - 5.days, last_activity_at: now - 140.days)
        conversation(status: :open, created_at: now - 6.days, last_activity_at: now - 30.days)

        result = report

        expect(result[:kpis][:stalled]).to eq(1)
        expect(result[:stalled].map { |row| row[:days] }).to eq([30])
      end
    end

    context 'when the inbox is commercial' do
      it 'keeps resolved conversations without an outcome — lá o board fecha por ganho/perdido' do
        conversation(status: :resolved, assignee: nil)
        conversation(status: :open, assignee: nil)

        expect(report[:kpis][:unassigned]).to eq(2)
      end

      it 'drops leads already closed with an outcome' do
        conversation(status: :open, assignee: nil, custom_attributes: { 'sdr_outcome' => 'won' })
        conversation(status: :open, assignee: nil)

        expect(report[:kpis][:unassigned]).to eq(1)
      end
    end

    it 'respects the selected period' do
      conversation(created_at: now - 3.days, assignee: nil)
      conversation(created_at: now - 40.days, assignee: nil)

      expect(report[:kpis][:unassigned]).to eq(1)
    end
  end

  describe 'SLA de 1º contato humano por área' do
    let(:fast_team) { create(:team, account: account, name: 'Crédito PJ') }
    let(:silent_team) { create(:team, account: account, name: 'Saúde') }

    # Entra em atendimento humano (label) e responde `minutes` depois.
    def measured_conversation(team:, minutes:)
      tagged_at = now - 1.day
      conv = conversation(team: team, created_at: now - 2.days)
      conv.update_columns(first_reply_created_at: tagged_at + minutes.minutes) # rubocop:disable Rails/SkipsModelValidations
      conv.update(label_list: ['atendimento_humano'])
      ActsAsTaggableOn::Tagging.where(taggable: conv).update_all(created_at: tagged_at) # rubocop:disable Rails/SkipsModelValidations
      conv
    end

    it 'lists every area with volume in the period, even without a measurable conversation' do
      measured_conversation(team: fast_team, minutes: 30)
      conversation(team: silent_team)

      rows = report[:sla][:by_product]

      expect(rows.map { |row| row[:product] }).to contain_exactly('Crédito PJ', 'Saúde')
      expect(rows.find { |row| row[:product] == 'Crédito PJ' }).to include(minutes: 30, measured: 1, total: 1)
      expect(rows.find { |row| row[:product] == 'Saúde' }).to include(minutes: nil, measured: 0, total: 1)
    end

    it 'exposes the sample size behind the overall average' do
      measured_conversation(team: fast_team, minutes: 30)
      conversation(team: fast_team)

      expect(report[:sla]).to include(avg_minutes: 30, measured: 1, total: 2, target_minutes: 45)
    end

    it 'ignores a reply that came before the human handoff' do
      conv = conversation(team: fast_team)
      conv.update_columns(first_reply_created_at: now - 3.days) # rubocop:disable Rails/SkipsModelValidations
      conv.update(label_list: ['atendimento_humano'])
      ActsAsTaggableOn::Tagging.where(taggable: conv).update_all(created_at: now - 1.day) # rubocop:disable Rails/SkipsModelValidations

      expect(report[:sla]).to include(avg_minutes: nil, measured: 0, total: 1)
    end
  end

  describe 'tempo médio na etapa' do
    before { Finture::PipelineStage.seed_defaults!(inbox, 'operacional') }

    it 'leaves out the stages that wait on the customer and names them' do
      conversation(custom_attributes: { 'sdr_stage' => 'em_triagem' }, created_at: now - 3.days)
      conversation(custom_attributes: { 'sdr_stage' => 'em_atendimento' }, created_at: now - 3.days)

      stage_time = report[:stage_time]

      expect(stage_time[:stages].map { |row| row[:slug] }).to eq(['em_atendimento'])
      expect(stage_time[:excluded]).to eq(['Em Triagem'])
    end

    it 'brings a stage back once it is switched on' do
      Finture::PipelineStage.find_by(inbox_id: inbox.id, slug: 'em_triagem').update!(counts_in_stage_time: true)
      conversation(custom_attributes: { 'sdr_stage' => 'em_triagem' }, created_at: now - 3.days)

      stage_time = report[:stage_time]

      expect(stage_time[:stages].map { |row| row[:slug] }).to include('em_triagem')
      expect(stage_time[:excluded]).not_to include('Em Triagem')
    end
  end
end
