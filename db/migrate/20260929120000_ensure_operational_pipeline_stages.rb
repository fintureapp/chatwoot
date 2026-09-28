# Backfill: caixas já classificadas como 'operacional' antes desta versão
# receberam a classificação sem o funil operacional (o seed só rodava em caixa
# sem etapas). Aplica Finture::PipelineStage.ensure_stages_for_type! nelas:
# renomeia a etapa travada para "Chamada Iniciada" e cria em_triagem /
# em_atendimento se faltarem. Não remove colunas nem altera slugs (cards
# preservados). Idempotente; irreversível por design (down é no-op).
class EnsureOperationalPipelineStages < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:finture_inbox_configs) && table_exists?(:finture_pipeline_stages)

    Finture::InboxConfig.where(kanban_type: 'operacional').includes(:inbox).find_each do |config|
      next if config.inbox.nil?

      Finture::PipelineStage.ensure_stages_for_type!(config.inbox, 'operacional')
    end
  end

  def down; end
end
