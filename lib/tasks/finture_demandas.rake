# Central de Demandas (Chatwoot → HUB): consulta e reconciliação dos envios.
# Detalhes em docs/finture-central-demandas.md.
#
#   bundle exec rake finture:demandas:pendencias
#   bundle exec rake "finture:demandas:reconciliar[50]"
#     lote; DRY_RUN=1 só lista; DRIFT=1 inclui synced cujo conteúdo mudou sem envio
#   bundle exec rake "finture:demandas:reconciliar_conversa[123]"
#     uma conversa (id interno), reenvio forçado

namespace :finture do
  namespace :demandas do
    desc 'Lista envios não aplicados no HUB (failed, divergent, retrying, pending) e recuperações em aberto'
    task pendencias: :environment do
      scope = Finture::DemandaSync.where.not(status: 'synced').or(Finture::DemandaSync.awaiting_recovery)
      scope.find_each do |sync|
        puts [sync.conversation_id, sync.external_id, sync.status, sync.hub_motivo, sync.recovery_state,
              sync.rejected_at&.iso8601, sync.recovered_at&.iso8601, sync.last_error.to_s.truncate(120)].join(' | ')
      end
    end

    desc 'Reenvia o estado atual das conversas failed/divergent/paradas, em lote (padrão 50)'
    task :reconciliar, [:limit] => :environment do |_task, args|
      result = Finture::DemandaReconcileService.new(
        limit: args[:limit], include_drift: ENV.fetch('DRIFT', nil) == '1', dry_run: ENV.fetch('DRY_RUN', nil) == '1'
      ).perform
      verb = result[:enqueued] ? 'enfileiradas' : 'selecionadas (DRY_RUN)'
      puts "#{result[:conversation_ids].size} conversas #{verb}, ocorrido_em #{result[:occurred_at]}: #{result[:conversation_ids].join(', ')}"
    end

    desc 'Reenvia agora o estado atual de UMA conversa (id interno), mesmo sem mudança de conteúdo'
    task :reconciliar_conversa, [:conversation_id] => :environment do |_task, args|
      abort 'informe o id da conversa: rake "finture:demandas:reconciliar_conversa[123]"' if args[:conversation_id].blank?

      result = Finture::DemandaReconcileService.reconcile_conversation!(args[:conversation_id].to_i)
      sync = Finture::DemandaSync.find_by(conversation_id: args[:conversation_id].to_i)
      puts "resultado: #{result.inspect}; status: #{sync&.status}; recuperação: #{sync&.recovery_state}"
    end
  end
end
