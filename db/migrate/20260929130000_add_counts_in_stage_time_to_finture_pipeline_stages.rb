# Marca, por etapa do funil, se ela entra no "Tempo médio na etapa" do Dashboard
# Operacional. Etapas de espera do cliente (Chamada Iniciada, Em Triagem) medem
# o tempo que o LEAD leva para responder / ser triado, não o nosso atendimento —
# contá-las junto inflava a média e escondia o gargalo real.
#
# Default true (preserva o comportamento das etapas existentes). O backfill
# desliga apenas as etapas de espera das caixas OPERACIONAIS: a etapa de entrada
# (travada, qualquer que seja o slug — caixa que virou operacional depois
# conserva o `lead_identificado` original) e a de triagem. Aditivo e reversível.
class AddCountsInStageTimeToFinturePipelineStages < ActiveRecord::Migration[7.1]
  def up
    add_column :finture_pipeline_stages, :counts_in_stage_time, :boolean, null: false, default: true
    return unless table_exists?(:finture_inbox_configs)

    execute(<<~SQL.squish)
      UPDATE finture_pipeline_stages AS stages
         SET counts_in_stage_time = false
        FROM finture_inbox_configs AS configs
       WHERE configs.inbox_id = stages.inbox_id
         AND configs.kanban_type = 'operacional'
         AND (stages.locked OR stages.slug IN ('chamada_iniciada', 'em_triagem'))
    SQL
  end

  def down
    remove_column :finture_pipeline_stages, :counts_in_stage_time
  end
end
