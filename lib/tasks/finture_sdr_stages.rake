# Tarefas aditivas do Kanban SDR (etapas por caixa + backfill de transições).
# Idempotentes — podem rodar mais de uma vez sem efeito colateral.
namespace :finture do
  namespace :sdr do
    desc 'Semeia o funil padrão (Lead Identificado + etapas herdadas) em cada caixa'
    task seed_stages: :environment do
      count = 0
      Inbox.find_each do |inbox|
        Finture::PipelineStage.seed_defaults!(inbox)
        count += 1
      end
      puts "Etapas semeadas/garantidas em #{count} caixa(s)."
    end
  end
end
