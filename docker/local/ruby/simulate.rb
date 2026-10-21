# frozen_string_literal: true

# Finture local — simulação ponta a ponta (rake finture:local:simulate).
# Pré-requisito: `make dev` rodando (rails, sidekiq, webhook-sink, mailpit).
#
# Fluxos:
#   A. WhatsApp: webhook Meta assinado -> Sidekiq cria contato/conversa -> automação
#      atribui time/etiqueta -> broadcast ActionCable (Redis) -> resposta do agente
#      pela API -> Sidekiq envia para a "Graph API" simulada (webhook-sink).
#   B. Status e atribuição via API.
#   C. Inbox API: contato/conversa/mensagem pela API pública -> resposta -> webhook no sink.
#   D. E-mail: entrada via Action Mailbox (Sidekiq) e resposta capturada no Mailpit;
#      recuperação de senha capturada no Mailpit.
#   E. Anexo: upload pela API, download pelo Active Storage local, exclusão.
require 'net/http'
require 'json'
require 'openssl'
require 'securerandom'

module FintureLocalSimulation
  BASE_URL = ENV.fetch('SIMULATION_BASE_URL', 'http://rails:3000')
  SINK_URL = 'http://webhook-sink:8080'
  MAILPIT_URL = 'http://mailpit:8025'
  FIXTURES = Rails.root.join('docker/local/fixtures')
  TIMEOUT = Integer(ENV.fetch('SIMULATION_TIMEOUT', 60))

  module_function

  def results
    @results ||= []
  end

  def record(name, ok, detail)
    results << [name, ok]
    puts format('%-6<status>s %<name>s — %<detail>s', status: ok ? 'PASS' : 'FAIL', name: name, detail: detail)
    ok
  end

  def wait_for(seconds = TIMEOUT)
    deadline = Time.current + seconds
    loop do
      value = yield
      return value if value
      return nil if Time.current > deadline

      sleep 1
    end
  end

  def http(method, url, body: nil, headers: {}, form: nil)
    uri = URI(url)
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method)
    request = klass.new(uri)
    headers.each { |k, v| request[k] = v }
    if form
      request.set_form(form, 'multipart/form-data')
    elsif body
      request['Content-Type'] = 'application/json'
      request.body = body.is_a?(String) ? body : body.to_json
    end
    Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) { |h| h.request(request) }
  end

  def json(response)
    JSON.parse(response.body.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def account
    @account ||= Account.find_by!(name: 'Finture (Local)')
  end

  def admin
    @admin ||= User.find_by!(email: 'admin@finture.example')
  end

  def api_headers
    { 'api_access_token' => admin.access_token.token }
  end

  def api(method, path, **)
    http(method, "#{BASE_URL}/api/v1/accounts/#{account.id}#{path}", headers: api_headers, **)
  end

  def sink_requests
    json(http(:get, "#{SINK_URL}/_requests"))['requests'] || []
  end

  def mailpit_search(query)
    json(http(:get, "#{MAILPIT_URL}/api/v1/search?query=#{ERB::Util.url_encode(query)}"))['messages'] || []
  end

  # Captura broadcasts do ActionCable direto no Redis local (prova server-side do realtime).
  def capture_cable_events(seconds)
    events = []
    thread = Thread.new do
      redis = Redis.new(**Redis::Config.app)
      redis.psubscribe_with_timeout(seconds, 'chatwoot_development_action_cable:*') do |on|
        on.pmessage { |_pattern, _channel, message| events << (JSON.parse(message)['event'] rescue nil) }
      end
    rescue Redis::TimeoutError
      nil
    end
    [thread, events]
  end

  # ------------------------------------------------------------------ A. WhatsApp
  def whatsapp_flow
    puts "\n== A. WhatsApp simulado"
    channel = Channel::Whatsapp.find_by!(phone_number: '+5500900000000')
    stamp = Time.current.strftime('%H%M%S')
    wa_id = '5500900000099'
    message_id = "wamid.SIMULADO#{SecureRandom.hex(8).upcase}"
    payload = File.read(FIXTURES.join('whatsapp_inbound_text.json'))
                  .gsub('{{DISPLAY_PHONE_NUMBER}}', channel.phone_number.delete('+'))
                  .gsub('{{PHONE_NUMBER_ID}}', channel.provider_config['phone_number_id'])
                  .gsub('{{CONTACT_NAME}}', 'Contato Simulado WhatsApp')
                  .gsub('{{WA_ID}}', wa_id)
                  .gsub('{{MESSAGE_ID}}', message_id)
                  .gsub('{{TIMESTAMP}}', Time.current.to_i.to_s)
                  .gsub('{{TEXT}}', "Olá, quero cotar um plano de saúde para 4 vidas (simulação #{stamp})")
    JSON.parse(payload) # fixture válida
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', channel.provider_config['app_secret'], payload)}"

    cable_thread, cable_events = capture_cable_events(TIMEOUT)
    response = http(:post, "#{BASE_URL}/webhooks/whatsapp/#{channel.phone_number}", body: payload,
                                                                                     headers: { 'X-Hub-Signature-256' => signature })
    record('webhook Meta assinado aceito', response.code == '200', "HTTP #{response.code}")

    unsigned = http(:post, "#{BASE_URL}/webhooks/whatsapp/#{channel.phone_number}", body: payload)
    record('webhook sem assinatura recusado', unsigned.code == '401', "HTTP #{unsigned.code}")

    message = wait_for { Message.find_by(source_id: message_id) }
    return record('Sidekiq criou a mensagem recebida', false, 'mensagem não apareceu') unless message

    conversation = message.conversation
    record('Sidekiq criou contato + conversa', true, "conversa ##{conversation.display_id}, contato #{conversation.contact.name}")

    automated = wait_for { conversation.reload.team&.name == 'saúde' && conversation.label_list.include?('saude') }
    record('automação atribuiu time Saúde + etiqueta', automated.present?,
           "time=#{conversation.team&.name.inspect} etiquetas=#{conversation.label_list.inspect} responsável=#{conversation.assignee&.name.inspect}")

    sink_before = sink_requests.size
    reply = api(:post, "/conversations/#{conversation.display_id}/messages", body: { content: "Resposta simulada #{stamp}", private: false })
    record('agente respondeu pela API', reply.code == '200', "HTTP #{reply.code}")

    delivered = wait_for do
      sink_requests.drop(sink_before).find { |r| r['method'] == 'POST' && r['url'].end_with?('/messages') && r.dig('body', 'text', 'body').to_s.include?(stamp) }
    end
    record('Sidekiq entregou ao WhatsApp simulado (sink)', delivered.present?, delivered ? "POST #{delivered['url']}" : 'nada capturado')

    reply_id = json(reply)['id']
    sent = wait_for { Message.find_by(id: reply_id)&.source_id&.start_with?('wamid.LOCAL') }
    record('mensagem enviada recebeu id do provider simulado', sent.present?, Message.find_by(id: reply_id)&.source_id.to_s)

    cable_thread.join(TIMEOUT + 5)
    record('realtime: broadcast message.created no ActionCable', cable_events.include?('message.created'),
           "eventos: #{cable_events.compact.uniq.first(6).join(', ')}")
    conversation
  end

  # ------------------------------------------------------------------ B. status/atribuição
  def status_and_assignment_flow(conversation)
    puts "\n== B. Status e atribuição"
    return record('status/atribuição', false, 'sem conversa do fluxo A') unless conversation

    # Sempre um agente diferente do atual: a troca precisa ser real para notificar
    # (zerar o responsável dispara a autoatribuição do fork e pode devolver o mesmo agente).
    candidates = %w[bruno.vida@finture.example carla.consorcio@finture.example].map { |email| User.find_by!(email: email) }
    agent = candidates.find { |user| user.id != conversation.reload.assignee_id }
    started_at = Time.current
    assign = api(:post, "/conversations/#{conversation.display_id}/assignments", body: { assignee_id: agent.id })
    record('atribuição a agente', assign.code == '200' && conversation.reload.assignee_id == agent.id, "responsável=#{conversation.assignee&.name}")

    %w[pending resolved open].each do |status|
      res = api(:post, "/conversations/#{conversation.display_id}/toggle_status", body: { status: status })
      record("status -> #{status}", res.code == '200' && conversation.reload.status == status, "HTTP #{res.code}")
    end

    # O fork colapsa notificações não lidas por conversa (RemoveDuplicateNotificationJob):
    # a de atribuição pode ser substituída por uma mais nova do mesmo agente.
    notified = wait_for { Notification.where(user: agent, primary_actor: conversation).where(created_at: started_at..).first }
    record('notificação para o agente atribuído (Sidekiq + sino)', notified.present?, notified ? "tipo #{notified.notification_type}" : 'sem notificação')
  end

  # ------------------------------------------------------------------ C. inbox API
  def api_inbox_flow
    puts "\n== C. Inbox API (pública) + webhook capturado"
    inbox = account.inboxes.find_by!(name: 'API Integração (simulada)')
    identifier = inbox.channel.identifier
    stamp = SecureRandom.hex(3)
    contact = json(http(:post, "#{BASE_URL}/public/api/v1/inboxes/#{identifier}/contacts",
                        body: { name: "Contato API #{stamp}", email: "api.#{stamp}@cliente.example" }))
    source_id = contact['source_id']
    record('contato criado pela API pública', source_id.present?, source_id.to_s)
    return unless source_id

    conv = json(http(:post, "#{BASE_URL}/public/api/v1/inboxes/#{identifier}/contacts/#{source_id}/conversations", body: {}))
    http(:post, "#{BASE_URL}/public/api/v1/inboxes/#{identifier}/contacts/#{source_id}/conversations/#{conv['id']}/messages",
         body: { content: "Mensagem recebida via API #{stamp}" })
    conversation = account.conversations.find_by(display_id: conv['id'])
    record('conversa + mensagem recebida', conversation&.messages&.incoming&.exists?, "conversa ##{conv['id']}")
    return unless conversation

    sink_before = sink_requests.size
    api(:post, "/conversations/#{conversation.display_id}/messages", body: { content: "Resposta API #{stamp}" })
    hook = wait_for do
      sink_requests.drop(sink_before).find { |r| r['url'].start_with?('/api-inbox') && r.dig('body', 'content').to_s.include?(stamp) }
    end
    record('webhook da inbox API capturado no sink', hook.present?, hook ? "evento #{hook.dig('body', 'event')}" : 'nada capturado')
  end

  # ------------------------------------------------------------------ D. e-mail
  def email_flow
    puts "\n== D. E-mail (Action Mailbox + Mailpit)"
    channel = Channel::Email.find_by!(email: 'operacional@finture.example')
    stamp = SecureRandom.hex(3)
    raw = File.read(FIXTURES.join('email_inbound.eml'))
              .gsub('{{FROM}}', "contato.email.#{stamp}@cliente.example")
              .gsub('{{TO}}', channel.email)
              .gsub('{{SUBJECT}}', "Solicitação simulada #{stamp}")
              .gsub('{{MESSAGE_ID}}', "#{SecureRandom.uuid}@cliente.example")
              .gsub('{{DATE}}', Time.current.rfc2822)
              .gsub('{{BODY}}', "Olá, preciso incluir um dependente. Código #{stamp}.")
    ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
    message = wait_for { Message.where(inbox_id: channel.inbox.id).where('content LIKE ?', "%#{stamp}%").first }
    record('e-mail recebido virou conversa (Sidekiq)', message.present?, message ? "conversa ##{message.conversation.display_id}" : 'não processado')

    if message
      api(:post, "/conversations/#{message.conversation.display_id}/messages", body: { content: "Resposta por e-mail #{stamp}" })
      mail = wait_for { mailpit_search(stamp).find { |m| m['Snippet'].to_s.include?(stamp) || m['Subject'].to_s.include?(stamp) } }
      record('resposta por e-mail capturada no Mailpit', mail.present?, mail ? "para #{mail.dig('To', 0, 'Address')}" : 'nada no Mailpit')
    end

    agent = User.find_by!(email: 'ana.saude@finture.example')
    agent.send_reset_password_instructions
    reset = wait_for { mailpit_search("to:#{agent.email}").find { |m| m['Subject'].to_s =~ /senha|password/i } }
    record('recuperação de senha capturada no Mailpit', reset.present?, reset ? reset['Subject'] : 'nada no Mailpit')
  end

  # ------------------------------------------------------------------ E. anexo
  def attachment_flow
    puts "\n== E. Anexo (Active Storage local)"
    conversation = account.conversations.find_by!("additional_attributes ->> 'finture_seed_key' = 'api-01'")
    content = "arquivo sintético #{SecureRandom.hex(4)}\n"
    upload = api(:post, "/conversations/#{conversation.display_id}/messages",
                 form: [['content', 'Anexo de teste'], ['private', 'true'],
                        ['attachments[]', StringIO.new(content), { filename: 'anexo-ficticio.txt', content_type: 'text/plain' }]])
    data = json(upload)
    attachment = data['attachments']&.first
    record('upload de anexo', upload.code == '200' && attachment.present?, "HTTP #{upload.code}")
    return unless attachment

    blob = Message.find(data['id']).attachments.first.file.blob
    path = ActiveStorage::Blob.service.path_for(blob.key)
    record('arquivo gravado no volume local', File.exist?(path), path.sub(Rails.root.to_s, '.'))
    download = blob.download
    record('download confere com o upload', download.b == content.b, "#{download.bytesize} bytes")

    destroy = api(:delete, "/conversations/#{conversation.display_id}/messages/#{data['id']}")
    purged = wait_for(30) { !ActiveStorage::Blob.exists?(blob.id) || !File.exist?(path) }
    record('exclusão do anexo', destroy.code == '200', purged ? 'blob removido' : 'mensagem excluída; purge do blob pendente na fila')
  end

  def run
    puts "[finture-local] Simulação em #{BASE_URL} (timeout #{TIMEOUT}s por etapa)"
    conversation = whatsapp_flow
    status_and_assignment_flow(conversation)
    api_inbox_flow
    email_flow
    attachment_flow
    failed = results.reject(&:last)
    puts "\n== Resultado: #{results.size - failed.size}/#{results.size} verificações passaram"
    exit(1) if failed.any?
  end
end

FintureLocalSimulation.run
