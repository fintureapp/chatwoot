# frozen_string_literal: true

# Finture — isolamento do ambiente local.
#
# Duas travas, ativas SÓ fora de produção:
#
# 1. Trava de boot (development sempre; test quando FINTURE_LOCAL_ISOLATION=enforce):
#    aborta a inicialização (server, Sidekiq, console, rake db:*) se banco, Redis,
#    SMTP, storage, FRONTEND_URL ou qualquer *_URL/*_HOST apontarem para fora da
#    allowlist local, ou se variáveis de credencial produtiva estiverem preenchidas.
#    As mensagens citam apenas NOMES de variáveis — nunca valores ou hosts.
#
# 2. Trava de egress (development): toda conexão TCP aberta por código Ruby
#    (Net::HTTP, HTTParty, Faraday, RestClient, Net::SMTP, redis-client...) só
#    pode ir para hosts da allowlist ou loopback. O resto levanta
#    FintureLocalIsolation::BlockedEgressError. Bibliotecas em C (libpq) ficam
#    cobertas pela trava de boot; no Docker local, Rails/Sidekiq/Vite também
#    rodam numa rede sem rota para a internet (docker-compose.local.yaml).
#
# Para liberar um host de sandbox conscientemente, use LOCAL_EGRESS_ALLOWLIST
# (lista separada por vírgula). Não existe chave para desligar as travas.
require 'ipaddr'
require 'socket'
require 'uri'

module FintureLocalIsolation # rubocop:disable Metrics/ModuleLength -- trava única e autocontida, revisada como um bloco
  class ViolationError < StandardError; end
  class BlockedEgressError < StandardError; end

  DEFAULT_ALLOWED_HOSTS = %w[
    localhost 127.0.0.1 ::1 0.0.0.0
    postgres redis mailpit webhook-sink vite rails sidekiq edge
  ].freeze

  # Credenciais/recursos que só fazem sentido em produção. Precisam estar vazias.
  FORBIDDEN_VARS = %w[
    AZURE_STORAGE_ACCOUNT_NAME AZURE_STORAGE_ACCESS_KEY AZURE_STORAGE_CONTAINER
    AZURE_APP_ID AZURE_APP_SECRET
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY S3_BUCKET_NAME
    GCS_PROJECT GCS_CREDENTIALS GCS_BUCKET
    STORAGE_ACCESS_KEY_ID STORAGE_SECRET_ACCESS_KEY STORAGE_BUCKET_NAME
    SMTP_USERNAME SMTP_PASSWORD
    FB_APP_ID FB_APP_SECRET FB_VERIFY_TOKEN IG_VERIFY_TOKEN
    INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN
    WHATSAPP_APP_ID WHATSAPP_APP_SECRET WHATSAPP_CONFIGURATION_ID
    TWITTER_APP_ID TWITTER_CONSUMER_KEY TWITTER_CONSUMER_SECRET TWITTER_ENVIRONMENT
    SLACK_CLIENT_ID SLACK_CLIENT_SECRET
    GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET
    OPENAI_API_KEY ANTHROPIC_API_KEY
    SENTRY_DSN NEW_RELIC_LICENSE_KEY SCOUT_KEY ELASTIC_APM_SECRET_TOKEN DD_API_KEY
    FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS
    STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET
    VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY
    REDIS_SENTINELS REDIS_SENTINEL_MASTER_NAME
    RAILS_INBOUND_EMAIL_PASSWORD MAILGUN_INGRESS_SIGNING_KEY MANDRILL_INGRESS_API_KEY
  ].freeze

  # Variáveis de sistema/ferramentas que terminam em _URL/_HOST mas não são do app.
  IGNORED_URL_VARS = %w[RUBY_DOWNLOAD_URL DOCKER_HOST].freeze
  IGNORED_URL_PREFIXES = %w[BUNDLE_ GEM_ NPM_ PNPM_ YARN_ HOMEBREW_ npm_ VSCODE_ GIT_].freeze
  URL_VAR_PATTERN = /(_URL|_HOST|_ENDPOINT|_ADDRESS|_SERVER)\z/

  SUSPICIOUS_DB_NAME = /(prod|prd|production|cloudify|azure|live)/i
  ALLOWED_STORAGE_SERVICES = ['', 'local', 'test'].freeze

  module_function

  def boot_guard_enabled?
    return false if Rails.env.production?
    return true if Rails.env.development?

    ENV['FINTURE_LOCAL_ISOLATION'] == 'enforce'
  end

  def egress_guard_enabled?
    Rails.env.development?
  end

  def allowed_hosts
    @allowed_hosts ||= (DEFAULT_ALLOWED_HOSTS + ENV.fetch('LOCAL_EGRESS_ALLOWLIST', '').split(',')).map { |h| h.strip.downcase }.reject(&:empty?).uniq
  end

  def allowed_host?(host)
    return true if host.nil? || host.to_s.empty?

    normalized = host.to_s.downcase.delete_prefix('[').delete_suffix(']')
    return true if allowed_hosts.include?(normalized)
    return true if loopback_ip?(normalized)

    allowed_ips.include?(normalized)
  end

  def loopback_ip?(value)
    IPAddr.new(value).loopback?
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    false
  end

  # SafeFetch e o Net::HTTP com ipaddr conectam pelo IP já resolvido; aceitamos
  # IPs que resolvem a partir dos nomes da allowlist (rede do compose).
  def allowed_ips
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return @allowed_ips if @allowed_ips && now - @allowed_ips_at < 30

    @allowed_ips_at = now
    @allowed_ips = allowed_hosts.flat_map do |name|
      Addrinfo.getaddrinfo(name, nil, nil, :STREAM).map(&:ip_address)
    rescue SocketError
      []
    end.uniq
  end

  def host_of(value)
    return nil if value.nil? || value.strip.empty?

    candidate = value.include?('://') ? value : "tcp://#{value}"
    URI.parse(candidate).host
  rescue URI::InvalidURIError
    value
  end

  # Flags como ENABLE_PUSH_RELAY_SERVER=false ou portas não são hosts.
  def non_host_value?(value)
    value.to_s.strip.match?(/\A(true|false|yes|no|on|off|enabled|disabled|\d+)\z/i)
  end

  def violations
    (service_violations + forbidden_var_violations + url_var_violations).uniq
  end

  def service_violations
    database_url = ENV.fetch('DATABASE_URL', '').to_s
    db_host = database_url.empty? ? ENV.fetch('POSTGRES_HOST', 'localhost') : host_of(database_url)
    checks = {
      'RAILS_ENV não pode ser production no ambiente local' => ENV.fetch('RAILS_ENV', nil) == 'production',
      'POSTGRES_HOST/DATABASE_URL aponta para host fora da allowlist local' => !allowed_host?(db_host),
      'POSTGRES_DATABASE tem nome com cara de produção' => ENV.fetch('POSTGRES_DATABASE', '').match?(SUSPICIOUS_DB_NAME),
      'REDIS_URL aponta para host fora da allowlist local' => !allowed_host?(host_of(ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'))),
      'SMTP_ADDRESS aponta para host fora da allowlist local' => !allowed_host?(ENV.fetch('SMTP_ADDRESS', '')),
      'ACTIVE_STORAGE_SERVICE precisa ser local' => ALLOWED_STORAGE_SERVICES.exclude?(ENV.fetch('ACTIVE_STORAGE_SERVICE', '')),
      'FORCE_SSL deve ficar desligado no ambiente local' => ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE_SSL', false))
    }
    checks.select { |_message, violated| violated }.keys
  end

  def forbidden_var_violations
    FORBIDDEN_VARS.reject { |name| ENV.fetch(name, '').to_s.strip.empty? }
                  .map { |name| "#{name} precisa ficar vazia no ambiente local" }
  end

  def url_var_violations
    ENV.keys.select { |name| checked_url_var?(name) && !allowed_host?(host_of(ENV.fetch(name, nil))) }
       .map { |name| "#{name} aponta para host fora da allowlist local" }
  end

  def checked_url_var?(name)
    return false unless name.match?(URL_VAR_PATTERN)
    return false if IGNORED_URL_VARS.include?(name) || IGNORED_URL_PREFIXES.any? { |prefix| name.start_with?(prefix) }

    !non_host_value?(ENV.fetch(name, nil))
  end

  def enforce_boot!
    return unless boot_guard_enabled?

    errors = violations
    return if errors.empty?

    raise ViolationError, <<~MSG
      [finture-local] Inicialização bloqueada: configuração não é exclusivamente local.
      #{errors.map { |e| "  - #{e}" }.join("\n")}
      Corrija o .env.local (veja .env.local.example e docs/LOCAL_DEVELOPMENT.md).
      Hosts aceitos: #{allowed_hosts.join(', ')} (estenda com LOCAL_EGRESS_ALLOWLIST).
    MSG
  end

  def check_egress!(host, port)
    return if allowed_host?(host)

    message = "[finture-local] Conexão externa bloqueada: #{host}:#{port}. " \
              'Use os mocks locais (webhook-sink/mailpit) ou LOCAL_EGRESS_ALLOWLIST para um sandbox autorizado.'
    Rails.logger&.warn(message)
    raise BlockedEgressError, message
  end

  module TCPSocketGuard
    def initialize(remote_host, remote_port, *, **kwargs)
      FintureLocalIsolation.check_egress!(remote_host, remote_port)
      kwargs.empty? ? super(remote_host, remote_port, *) : super
    end
  end

  module SocketTcpGuard
    def tcp(host, port, *, **, &)
      FintureLocalIsolation.check_egress!(host, port)
      super
    end
  end

  def install_egress_guard!
    return unless egress_guard_enabled?
    return if @egress_guard_installed

    TCPSocket.prepend(TCPSocketGuard)
    Socket.singleton_class.prepend(SocketTcpGuard)
    @egress_guard_installed = true
  end
end

FintureLocalIsolation.enforce_boot!
FintureLocalIsolation.install_egress_guard!
