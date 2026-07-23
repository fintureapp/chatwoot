# Tarefas aditivas do Kanban SDR (etapas por caixa + backfill de desfechos e
# transições). Idempotentes — podem rodar mais de uma vez sem efeito colateral.
# Rodar UMA vez após o deploy que sobe as Fases B/C:
#   bundle exec rake finture:sdr:setup
namespace :finture do
  namespace :sdr do
    TERMINAL_STAGES = { 'ganho' => 'won', 'perdido' => 'lost' }.freeze

    desc 'Semeia o funil padrão (Lead Identificado + etapas herdadas) em cada caixa'
    task seed_stages: :environment do
      count = 0
      Inbox.find_each do |inbox|
        Finture::PipelineStage.seed_defaults!(inbox)
        count += 1
      end
      puts "Etapas semeadas/garantidas em #{count} caixa(s)."
    end

    desc 'Converte leads em ganho/perdido para desfecho (sdr_outcome) e reconstrói as transições a partir do sdr_history'
    task backfill: :environment do
      converted = migrate_outcomes
      transitions = backfill_transitions
      puts "#{converted} desfecho(s) convertido(s); #{transitions} transição(ões) reconstruída(s)."
    end

    desc 'Seed de etapas + backfill de desfechos/transições (idempotente)'
    task setup: %i[seed_stages backfill]

    # ganho/perdido (etapa antiga) -> sdr_outcome; sdr_stage volta à última etapa real.
    def migrate_outcomes
      count = 0
      Conversation.where("custom_attributes ->> 'sdr_stage' IN ('ganho','perdido')").find_each do |conversation|
        attrs = conversation.custom_attributes || {}
        next if attrs['sdr_outcome'].present?

        outcome = TERMINAL_STAGES[attrs['sdr_stage']]
        history = attrs['sdr_history'].is_a?(Array) ? attrs['sdr_history'] : []
        closing = history.reverse.find { |entry| TERMINAL_STAGES.key?(entry['to']) }

        attrs['sdr_stage'] = closing&.dig('from').presence || Finture::PipelineStage::DEFAULT_SLUG
        attrs['sdr_outcome'] = outcome
        attrs['sdr_outcome_at'] = closing&.dig('at') || conversation.updated_at.to_i
        attrs['sdr_lost_reason'] ||= closing['reason'] if outcome == 'lost' && closing&.dig('reason').present?
        conversation.update_columns(custom_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
        count += 1
      end
      count
    end

    # Reconstrói finture_stage_transitions a partir do sdr_history (só se a conversa
    # ainda não tem transições — mantém idempotência).
    def backfill_transitions
      count = 0
      Conversation.where("custom_attributes -> 'sdr_history' IS NOT NULL").find_each do |conversation|
        next if Finture::StageTransition.exists?(conversation_id: conversation.id)

        history = conversation.custom_attributes['sdr_history']
        next unless history.is_a?(Array)

        history.each do |entry|
          count += 1 if create_transition_from_history(conversation, entry)
        end
      end
      count
    end

    def create_transition_from_history(conversation, entry)
      to = entry['to']
      terminal = TERMINAL_STAGES.key?(to)
      Finture::StageTransition.create!(
        account_id: conversation.account_id,
        conversation_id: conversation.id,
        inbox_id: conversation.inbox_id,
        from_stage: entry['from'],
        to_stage: terminal ? (entry['from'].presence || Finture::PipelineStage::DEFAULT_SLUG) : to,
        to_stage_label: terminal ? (entry['from'].presence || Finture::PipelineStage::DEFAULT_SLUG) : to,
        kind: terminal ? TERMINAL_STAGES[to] : 'stage_change',
        reason: entry['reason'],
        comment: entry['comment'],
        source: entry['origin'] == 'n8n' ? 'n8n' : 'agent',
        occurred_at: entry['at'] ? Time.zone.at(entry['at']) : conversation.created_at
      )
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
