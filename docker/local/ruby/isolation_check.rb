# frozen_string_literal: true

# Finture local — prova executável do isolamento (rake finture:local:check).
# Todos os destinos "externos" abaixo são FICTÍCIOS ou públicos genéricos: o
# objetivo é provar que nenhuma conexão sai, sem nunca usar endereços reais de
# produção da Finture.
require 'open3'
require 'net/http'
require 'timeout'

results = []
record = lambda do |name, ok, detail|
  results << [name, ok, detail]
  puts format('%-6<status>s %<name>s — %<detail>s', status: ok ? 'PASS' : 'FAIL', name: name, detail: detail)
end

puts '== 1. Configuração efetiva (somente valores locais)'
db = ActiveRecord::Base.connection_db_config.configuration_hash
puts "  banco: #{db[:database]}@#{db[:host]}:#{db[:port]}"
puts "  redis: #{FintureLocalIsolation.host_of(ENV.fetch('REDIS_URL', nil))}"
puts "  smtp: #{ENV.fetch('SMTP_ADDRESS', '(vazio)')}:#{ENV.fetch('SMTP_PORT', '')}"
puts "  storage: #{Rails.application.config.active_storage.service}"
puts "  allowlist: #{FintureLocalIsolation.allowed_hosts.join(', ')}"

puts "\n== 2. Trava de boot no processo atual"
violations = FintureLocalIsolation.violations
record.call('boot guard (config atual)', violations.empty?, violations.empty? ? 'nenhuma violação' : violations.join('; '))

puts "\n== 3. Trava de egress Ruby (destinos fictícios/genéricos)"
{
  'Meta Graph API (WhatsApp)' => ['graph.facebook.com', 443],
  'Chatwoot Hub' => ['hub.2.chatwoot.com', 443],
  'PostgreSQL remoto (fictício)' => ['db-producao.cloudify.example', 5432],
  'Azure Blob (fictício)' => ['contaficticia.blob.core.windows.net', 443],
  'SMTP externo (genérico)' => ['smtp.office365.com', 587],
  'n8n externo (fictício)' => ['n8n.finture.example', 443],
  'Redis remoto (fictício)' => ['redis-producao.example', 6380]
}.each do |label, (host, port)|
  begin
    TCPSocket.new(host, port, connect_timeout: 3).close
    record.call("egress #{label}", false, "conectou em #{host}:#{port} — NÃO bloqueado")
  rescue FintureLocalIsolation::BlockedEgressError
    record.call("egress #{label}", true, 'bloqueado pela trava Ruby')
  rescue StandardError => e
    record.call("egress #{label}", false, "erro inesperado #{e.class}")
  end
end

begin
  Net::HTTP.get(URI('https://graph.facebook.com/v13.0/me'))
  record.call('egress Net::HTTP', false, 'requisição saiu')
rescue FintureLocalIsolation::BlockedEgressError
  record.call('egress Net::HTTP', true, 'Net::HTTP bloqueado')
end

begin
  ActionMailer::Base.smtp_settings.then { |s| record.call('ActionMailer SMTP -> mailpit', s[:address] == 'mailpit', "address=#{s[:address]}") }
end

puts "\n== 4. Rede Docker (sem a trava Ruby: socket cru, IP público)"
begin
  sock = Socket.new(:INET, :STREAM)
  addr = Socket.sockaddr_in(443, '1.1.1.1')
  Timeout.timeout(4) { sock.connect(addr) }
  record.call('rede interna sem internet', false, 'socket cru alcançou 1.1.1.1:443 — container com rota para a internet')
rescue Timeout::Error, Errno::ENETUNREACH, Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
  record.call('rede interna sem internet', true, "sem rota (#{e.class})")
ensure
  sock&.close
end

puts "\n== 5. Boot com configuração produtiva simulada deve falhar"
{
  'POSTGRES_HOST externo' => { 'POSTGRES_HOST' => 'db-producao.cloudify.example' },
  'nome de banco produtivo' => { 'POSTGRES_DATABASE' => 'chatwoot_production' },
  'REDIS_URL externo' => { 'REDIS_URL' => 'rediss://redis-producao.example:6380' },
  'SMTP externo' => { 'SMTP_ADDRESS' => 'smtp.office365.com' },
  'credencial Azure Storage' => { 'ACTIVE_STORAGE_SERVICE' => 'microsoft', 'AZURE_STORAGE_ACCESS_KEY' => 'valor-ficticio' },
  'webhook externo em *_URL' => { 'N8N_WEBHOOK_URL' => 'https://n8n.finture.example/webhook/x' }
}.each do |label, env|
  output, status = Open3.capture2e(env, 'ruby', 'bin/rails', 'runner', 'puts :booted', chdir: Rails.root.to_s)
  blocked = !status.success? && output.include?('Inicialização bloqueada')
  record.call("boot bloqueado: #{label}", blocked, blocked ? 'abortou antes de conectar' : 'NÃO abortou')
end

failed = results.reject { |r| r[1] }
puts "\n== Resultado: #{results.size - failed.size}/#{results.size} verificações passaram"
exit(1) if failed.any?
