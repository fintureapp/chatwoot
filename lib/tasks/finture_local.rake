# frozen_string_literal: true

# Finture — tarefas do ambiente LOCAL (docker-compose.local.yaml).
# Nenhuma delas roda fora de development/test com FINTURE_LOCAL_ISOLATION=enforce.
def finture_local_only!
  return if (Rails.env.development? || Rails.env.test?) && ENV.fetch('FINTURE_LOCAL_ISOLATION', nil) == 'enforce'

  abort '[finture-local] Tarefa exclusiva do ambiente Docker local (FINTURE_LOCAL_ISOLATION=enforce).'
end

namespace :finture do
  namespace :local do
    desc 'Aplica as seeds sintéticas Finture (idempotente)'
    task seed: :environment do
      finture_local_only!
      load Rails.root.join('db/seeds/finture_local.rb')
      FintureLocalSeeder.run!
    end

    desc 'Falha se o banco configurado não for o banco local do compose (usado pelo db-reset)'
    task assert_safe_db: :environment do
      finture_local_only!
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      host = config[:host].to_s
      database = config[:database].to_s
      safe = host == 'postgres' && database.match?(/\Achatwoot_local_(dev|test)\z/) &&
             !database.match?(FintureLocalIsolation::SUSPICIOUS_DB_NAME)
      abort '[finture-local] Reset recusado: o banco alvo não é o PostgreSQL local do compose.' unless safe

      puts "[finture-local] Banco alvo confirmado como local: #{database}@#{host}"
    end

    desc 'Relatório de isolamento: trava de boot, egress Ruby e rede Docker'
    task check: :environment do
      finture_local_only!
      load Rails.root.join('docker/local/ruby/isolation_check.rb')
    end

    desc 'Simula o fluxo completo (WhatsApp/API/e-mail -> conversa -> automação -> Sidekiq -> realtime -> resposta capturada)'
    task simulate: :environment do
      finture_local_only!
      load Rails.root.join('docker/local/ruby/simulate.rb')
    end
  end
end
