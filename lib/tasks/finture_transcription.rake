# Avaliação do motor de transcrição numa amostra de áudios (Finture::TranscriptionSample).
#   rake "finture:transcription:sample[/caminho/da/pasta]"
# Na pasta: os áudios (ogg, mp3, m4a, wav...) e, opcionalmente, <áudio>.txt com o
# texto esperado. Usa as mesmas variáveis FINTURE_TRANSCRIPTION_* da produção.
namespace :finture do
  namespace :transcription do
    desc 'Transcreve uma pasta de áudios e mede precisão, tempo e custo'
    task :sample, [:dir] => :environment do |_task, args|
      abort 'Informe a pasta: rake "finture:transcription:sample[/caminho]"' if args[:dir].blank?
      abort 'Configure FINTURE_TRANSCRIPTION_API_KEY (e o endpoint).' unless Finture::TranscriptionClient.configured?

      summary = Finture::TranscriptionSample.new(dir: args[:dir]).run
      summary.each { |key, value| puts "#{key}: #{value}" }
    end
  end
end
