# frozen_string_literal: true

# Finture — seeds SINTÉTICAS para o ambiente local (rake finture:local:seed).
#
# - Determinísticas e idempotentes: rodar de novo não duplica nada (chaves
#   estáveis em e-mail, identifier e additional_attributes.finture_seed_key).
# - Só identidades fictícias: domínios .example (RFC 2606), telefones com DDD 00,
#   nenhum CPF, nenhuma mensagem ou arquivo real.
# - Canais "simulados": WhatsApp Cloud apontado para o webhook-sink local
#   (WHATSAPP_CLOUD_BASE_URL), inbox API com webhook no sink, e-mail sem IMAP/SMTP
#   próprios (respostas saem pelo Mailpit). Nenhum webhook/credencial real.
class FintureLocalSeeder
  ACCOUNT_NAME = 'Finture (Local)'
  DOMAIN = 'finture.example'
  CLIENT_DOMAIN = 'cliente.example'
  WHATSAPP_NUMBER = '+5500900000000'
  WHATSAPP_PHONE_NUMBER_ID = 'local-phone-number-id'
  WHATSAPP_APP_SECRET = 'local-simulated-app-secret' # fictício: usado só para assinar webhooks simulados
  SINK_URL = 'http://webhook-sink:8080'

  TEAMS = {
    saude: 'Saúde',
    vida: 'Vida',
    consorcio: 'Consórcio/Crédito',
    corporate: 'Corporate',
    elementares: 'Elementares'
  }.freeze

  # [chave, nome, e-mail, papel, times]
  USERS = [
    [:admin, 'Admin Finture (Local)', "admin@#{DOMAIN}", :administrator, TEAMS.keys],
    [:supervisor, 'Sofia Supervisora', "supervisora@#{DOMAIN}", :administrator, %i[saude vida]],
    [:ana, 'Ana Saúde', "ana.saude@#{DOMAIN}", :agent, %i[saude]],
    [:bruno, 'Bruno Vida', "bruno.vida@#{DOMAIN}", :agent, %i[vida]],
    [:carla, 'Carla Consórcio', "carla.consorcio@#{DOMAIN}", :agent, %i[consorcio]],
    [:diego, 'Diego Corporate', "diego.corporate@#{DOMAIN}", :agent, %i[corporate]],
    [:elisa, 'Elisa Elementares', "elisa.elementares@#{DOMAIN}", :agent, %i[elementares]],
    # Cenário de permissão: agente sem time e sem caixa — não deve ver conversas.
    [:sem_acesso, 'Gabriel Sem Acesso', "sem.acesso@#{DOMAIN}", :agent, []]
  ].freeze

  LABELS = {
    'saude' => '#16a34a', 'vida' => '#2563eb', 'consorcio' => '#d97706', 'corporate' => '#7c3aed',
    'elementares' => '#0891b2', 'cotacao' => '#db2777', 'urgente' => '#dc2626', 'atendimento_humano' => '#475569'
  }.freeze

  # 1x1 PNG transparente — avatar/anexo sintético.
  PNG_PIXEL = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==')

  def self.run!
    new.run!
  end

  def run!
    assert_local_environment!
    ActiveRecord::Base.transaction do
      @account = seed_account
      @users = seed_users
      @teams = seed_teams
      seed_labels
      seed_custom_attributes
      @inboxes = seed_inboxes
      seed_inbox_members
      seed_finture_inbox_configs
      seed_channel_groups
      seed_automation_rules
      seed_canned_responses
      seed_conversations
      seed_notifications
    end
    print_summary
  end

  private

  attr_reader :account, :users, :teams, :inboxes

  def assert_local_environment!
    raise 'FintureLocalSeeder só roda em development/test.' unless Rails.env.development? || Rails.env.test?
    raise 'FintureLocalSeeder exige FINTURE_LOCAL_ISOLATION=enforce (Docker local).' unless ENV['FINTURE_LOCAL_ISOLATION'] == 'enforce'
  end

  def seed_password
    ENV.fetch('LOCAL_SEED_PASSWORD', 'Finture@Local2026')
  end

  # ---------------------------------------------------------------- conta/usuários
  def seed_account
    Account.find_or_create_by!(name: ACCOUNT_NAME) do |acc|
      acc.locale = 'pt_BR'
      acc.domain = DOMAIN
      acc.support_email = "suporte@#{DOMAIN}"
    end
  end

  def seed_users
    USERS.to_h do |key, name, email, role, _teams|
      user = User.find_by(email: email) || begin
        u = User.new(name: name, email: email, password: seed_password, password_confirmation: seed_password)
        u.type = 'SuperAdmin' if key == :admin # acesso a /super_admin e /monitoring/sidekiq no local
        u.skip_confirmation!
        u.save!
        u
      end
      AccountUser.find_or_create_by!(account: account, user: user) { |au| au.role = role }
      [key, user]
    end
  end

  def seed_teams
    team_records = TEAMS.to_h do |key, name|
      [key, Team.find_or_create_by!(account: account, name: name.downcase) { |t| t.description = "Time #{name} (fictício)" }]
    end
    USERS.each do |key, _name, _email, _role, team_keys|
      team_keys.each do |team_key|
        TeamMember.find_or_create_by!(team: team_records[team_key], user: users[key])
      end
    end
    team_records
  end

  def seed_labels
    LABELS.each do |title, color|
      Label.find_or_create_by!(account: account, title: title) do |label|
        label.color = color
        label.description = "Etiqueta #{title} (seed local)"
        label.show_on_sidebar = true
      end
    end
  end

  def seed_custom_attributes
    [
      ['produto', 'Produto', :list, :conversation_attribute, %w[Saúde Vida Consórcio Crédito Corporate Elementares]],
      ['origem_lead', 'Origem do lead', :list, :conversation_attribute, %w[Meta\ Ads Site Indicação Outbound]],
      ['valor_potencial', 'Valor potencial', :currency, :conversation_attribute, []],
      ['modo_atendimento', 'Modo de atendimento', :list, :conversation_attribute, %w[humano ia]],
      ['empresa', 'Empresa', :text, :contact_attribute, []]
    ].each do |key, display, type, model, values|
      CustomAttributeDefinition.find_or_create_by!(account: account, attribute_key: key, attribute_model: model) do |definition|
        definition.attribute_display_name = display
        definition.attribute_display_type = type
        definition.attribute_values = values
      end
    end
  end

  # ---------------------------------------------------------------- caixas
  def seed_inboxes
    {
      whatsapp: whatsapp_inbox,
      email: email_inbox,
      api: api_inbox,
      web: web_inbox
    }
  end

  def whatsapp_inbox
    channel = Channel::Whatsapp.find_by(phone_number: WHATSAPP_NUMBER)
    unless channel
      channel = Channel::Whatsapp.new(
        account: account,
        phone_number: WHATSAPP_NUMBER,
        provider: 'whatsapp_cloud',
        provider_config: {
          'api_key' => 'local-fake-token',
          'phone_number_id' => WHATSAPP_PHONE_NUMBER_ID,
          'business_account_id' => 'local-waba-id',
          'app_secret' => WHATSAPP_APP_SECRET,
          'source' => 'finture_local_simulation'
        }
      )
      # O cadastro de webhooks na Meta usa URL fixa da Graph API; no local não existe Meta.
      channel.define_singleton_method(:should_auto_setup_webhooks?) { false }
      channel.save!
    end
    Inbox.find_by(channel: channel) || Inbox.create!(account: account, channel: channel, name: 'WhatsApp Comercial (simulado)')
  end

  def email_inbox
    channel = Channel::Email.find_by(email: "operacional@#{DOMAIN}") ||
              Channel::Email.create!(account: account, email: "operacional@#{DOMAIN}")
    Inbox.find_by(channel: channel) || Inbox.create!(account: account, channel: channel, name: 'E-mail Operacional (simulado)')
  end

  def api_inbox
    inbox = account.inboxes.find_by(name: 'API Integração (simulada)')
    return inbox if inbox

    channel = Channel::Api.create!(account: account, webhook_url: "#{SINK_URL}/api-inbox")
    Inbox.create!(account: account, channel: channel, name: 'API Integração (simulada)')
  end

  def web_inbox
    inbox = account.inboxes.find_by(name: 'Site Finture (widget)')
    return inbox if inbox

    channel = Channel::WebWidget.create!(account: account, website_url: "https://www.#{DOMAIN}")
    Inbox.create!(account: account, channel: channel, name: 'Site Finture (widget)')
  end

  def seed_inbox_members
    members = %i[admin supervisor ana bruno carla diego elisa]
    inboxes.each_value do |inbox|
      members.each { |key| InboxMember.find_or_create_by!(inbox: inbox, user: users[key]) }
    end
  end

  def seed_finture_inbox_configs
    { whatsapp: 'comercial', api: 'comercial', web: 'comercial', email: 'operacional' }.each do |key, type|
      inbox = inboxes[key]
      Finture::InboxConfig.find_or_create_by!(inbox: inbox) do |config|
        config.account = account
        config.kanban_type = type
      end
      Finture::PipelineStage.seed_defaults!(inbox, type)
    end
  end

  def seed_channel_groups
    groups = { inboxes[:whatsapp].id.to_s => 'whatsapp', inboxes[:api].id.to_s => 'whatsapp', inboxes[:email].id.to_s => 'email' }
    attrs = account.custom_attributes || {}
    return if attrs['channel_groups'] == groups

    account.update!(custom_attributes: attrs.merge('channel_groups' => groups))
  end

  # contato -> conversa -> automação -> atribuição: mensagens recebidas com
  # "saúde" vão para o time Saúde com a etiqueta saude (idem consórcio).
  # Regra reaplicada a cada seed: mudanças aqui chegam a bancos já semeados.
  def seed_automation_rules
    [%w[saúde saude], %w[consórcio consorcio]].each do |word, team_key|
      team = teams[team_key.to_sym]
      rule = AutomationRule.find_or_initialize_by(account: account, name: "Triagem local: #{team_key}")
      rule.update!(
        description: 'Regra sintética do ambiente local', event_name: 'message_created', active: true,
        conditions: [
          { 'attribute_key' => 'content', 'filter_operator' => 'contains', 'values' => [word], 'query_operator' => 'AND' },
          { 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to', 'values' => ['incoming'], 'query_operator' => nil }
        ],
        actions: [
          { 'action_name' => 'assign_team', 'action_params' => [team.id] },
          { 'action_name' => 'add_label', 'action_params' => [team_key] }
        ]
      )
    end
  end

  def seed_canned_responses
    {
      'boasvindas' => 'Olá! Aqui é da Finture (ambiente local). Como posso ajudar?',
      'cotacao' => 'Para a cotação, preciso do número de vidas e das faixas etárias. (texto fictício)'
    }.each do |code, content|
      CannedResponse.find_or_create_by!(account: account, short_code: code) { |c| c.content = content }
    end
  end

  # ---------------------------------------------------------------- conversas
  CONVERSATIONS = [
    { key: 'wa-01', inbox: :whatsapp, contact: 1, status: :open, team: :saude, assignee: :ana, labels: %w[saude cotacao],
      stage: 'primeiro_contato', quote: { product_type: 'saude_pme', total_value: 4890.5,
                                          data: { 'lives' => { '24-28' => 3, '29-33' => 2 }, 'accommodation' => 'apartamento' } },
      follow_up: true, attachment: :image, priority: 'high',
      messages: [[:in, 'Olá, quero cotar um plano de saúde para minha empresa (5 vidas).'],
                 [:out, 'Olá! Claro. Pode me informar as idades dos beneficiários?'],
                 [:in, 'São 3 pessoas entre 24 e 28 anos e 2 entre 29 e 33.'],
                 [:note, 'Lead quente, já tem plano atual com reajuste alto. (nota fictícia)']] },
    { key: 'wa-02', inbox: :whatsapp, contact: 2, status: :pending, team: :vida, labels: %w[vida],
      messages: [[:in, 'Bom dia, vocês fazem seguro de vida individual?']] },
    { key: 'wa-03', inbox: :whatsapp, contact: 3, status: :open, team: :consorcio, assignee: :carla, labels: %w[consorcio cotacao],
      stage: 'proposta_enviada', quote: { product_type: 'consorcio', total_value: 250_000, data: { 'prazo_meses' => 180 } },
      messages: [[:in, 'Tenho interesse em consórcio de imóvel de 250 mil.'],
                 [:out, 'Perfeito, enviei a simulação por aqui. Conseguiu ver?']] },
    { key: 'wa-04', inbox: :whatsapp, contact: 4, status: :resolved, team: :corporate, assignee: :diego, labels: %w[corporate],
      outcome: 'won', messages: [[:in, 'Fechado, pode seguir com a proposta.'], [:out, 'Ótimo! Contrato enviado.']] },
    { key: 'wa-05', inbox: :whatsapp, contact: 5, status: :snoozed, team: :elementares, assignee: :elisa, labels: %w[elementares],
      messages: [[:in, 'Me chama na semana que vem para falar do seguro do carro.']] },
    { key: 'wa-06', inbox: :whatsapp, contact: 6, status: :open, team: :saude, labels: %w[saude atendimento_humano urgente],
      messages: [[:in, 'Preciso falar com um atendente humano, por favor.']] },
    { key: 'wa-07', inbox: :whatsapp, contact: 7, status: :resolved, team: :vida, assignee: :bruno, labels: %w[vida],
      outcome: 'lost', lost_reason: 'preco_condicao', messages: [[:in, 'Achei caro, vou ficar com o atual.']] },
    { key: 'em-01', inbox: :email, contact: 8, status: :open, team: :corporate, assignee: :diego, labels: %w[corporate],
      attachment: :text, messages: [[:in, 'Segue em anexo a lista de colaboradores para inclusão (arquivo fictício).'],
                                    [:out, 'Recebido, vamos processar as inclusões.']] },
    { key: 'em-02', inbox: :email, contact: 9, status: :resolved, team: :saude, assignee: :ana, labels: %w[saude],
      messages: [[:in, 'Solicito a segunda via do boleto.'], [:out, 'Segunda via enviada.']] },
    { key: 'em-03', inbox: :email, contact: 10, status: :pending, team: :elementares, labels: %w[elementares urgente], priority: 'urgent',
      messages: [[:in, 'Sinistro do imóvel: preciso abrir o aviso hoje.']] },
    { key: 'api-01', inbox: :api, contact: 11, status: :open, team: :vida, assignee: :bruno, labels: %w[vida],
      messages: [[:in, 'Mensagem recebida pela integração (simulada).'], [:out, 'Resposta que vai para o webhook-sink local.']] },
    { key: 'web-01', inbox: :web, contact: 12, status: :open, labels: [],
      messages: [[:in, 'Oi! Vim pelo site e quero saber sobre consórcio.']] }
  ].freeze

  CONTACT_NAMES = [
    'Mariana Teixeira', 'Rafael Moura', 'Juliana Prado', 'Construtora Exemplo Ltda', 'Pedro Alcântara', 'Luciana Faria',
    'Thiago Rezende', 'Indústria Fictícia S.A.', 'Camila Duarte', 'Condomínio Jardim Exemplo', 'Parceiro Integração Teste',
    'Visitante do Site'
  ].freeze

  def seed_conversations
    CONVERSATIONS.each { |spec| seed_conversation(spec) }
  end

  def seed_conversation(spec)
    return if Conversation.where(account: account).exists?(["additional_attributes ->> 'finture_seed_key' = ?", spec[:key]])

    inbox = inboxes[spec[:inbox]]
    contact_inbox = build_contact_inbox(inbox, spec[:contact])
    conversation = Conversation.create!(
      account: account, inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox,
      status: :open, team: spec[:team] && teams[spec[:team]], assignee: spec[:assignee] && users[spec[:assignee]],
      additional_attributes: { 'finture_seed_key' => spec[:key] },
      custom_attributes: { 'origem_lead' => 'Meta Ads', 'modo_atendimento' => spec[:assignee] ? 'humano' : 'ia' }
    )
    seed_messages(conversation, spec)
    conversation.add_labels(spec[:labels]) if spec[:labels].any?
    conversation.update!(priority: spec[:priority]) if spec[:priority]
    seed_sdr(conversation, spec)
    apply_status(conversation, spec[:status])
  end

  def build_contact_inbox(inbox, index)
    name = CONTACT_NAMES[index - 1]
    slug = format('contato%02d', index)
    phone = format('+55009000%05d', index)
    source_id = case inbox.channel_type
                when 'Channel::Whatsapp' then phone.delete('+')
                when 'Channel::Email' then "#{slug}@#{CLIENT_DOMAIN}"
                else "finture-seed-#{slug}"
                end
    contact_inbox = ContactInbox.find_by(inbox: inbox, source_id: source_id)
    return contact_inbox if contact_inbox

    ContactInboxWithContactBuilder.new(
      source_id: source_id, inbox: inbox, hmac_verified: true,
      contact_attributes: {
        name: name, email: "#{slug}@#{CLIENT_DOMAIN}", phone_number: phone, identifier: "finture-seed-#{slug}",
        custom_attributes: { 'empresa' => name.include?('Ltda') || name.include?('S.A.') ? name : 'Pessoa física (fictícia)' }
      }
    ).perform.tap { |ci| attach_avatar(ci.contact) if index == 1 }
  end

  def seed_messages(conversation, spec)
    agent = conversation.assignee || users[:admin]
    spec[:messages].each_with_index do |(kind, content), index|
      attrs = { account: account, inbox: conversation.inbox, conversation: conversation, content: content }
      message = case kind
                when :in then Message.new(attrs.merge(message_type: :incoming, sender: conversation.contact))
                when :out then Message.new(attrs.merge(message_type: :outgoing, sender: agent))
                when :note then Message.new(attrs.merge(message_type: :outgoing, sender: agent, private: true))
                end
      attach_file(message, spec[:attachment]) if spec[:attachment] && index.zero?
      message.save!
    end
  end

  def attach_file(message, kind)
    io, filename, content_type, file_type =
      if kind == :image
        [StringIO.new(PNG_PIXEL), 'foto-ficticia.png', 'image/png', :image]
      else
        [StringIO.new("nome;cargo\nColaborador Fictício 1;Analista\nColaborador Fictício 2;Gerente\n"), 'lista-ficticia.csv', 'text/csv', :file]
      end
    message.attachments.new(account_id: account.id, file_type: file_type, file: { io: io, filename: filename, content_type: content_type })
  end

  def attach_avatar(contact)
    contact.avatar.attach(io: StringIO.new(PNG_PIXEL), filename: 'avatar-ficticio.png', content_type: 'image/png') unless contact.avatar.attached?
  end

  def seed_sdr(conversation, spec)
    user = conversation.assignee || users[:admin]
    Finture::StageChangeService.new(conversation: conversation, to_stage: spec[:stage], source: 'agent', user: user).perform if spec[:stage]
    if spec[:quote]
      Finture::QuoteUpsertService.new(conversation: conversation.reload, params: spec[:quote], source: 'agent').perform
    end
    if spec[:follow_up]
      Finture::FollowUp.create!(account: account, conversation: conversation, user: user, title: 'Retornar com a cotação (fictício)',
                                due_at: 2.days.from_now.change(hour: 14))
      Finture::FollowUp.sync_mirror!(conversation.reload)
    end
    return unless spec[:outcome]

    Finture::OutcomeService.new(conversation: conversation.reload, kind: spec[:outcome], user: user, reason: spec[:lost_reason]).perform
  end

  def apply_status(conversation, status)
    case status
    when :pending then conversation.update!(status: :pending)
    when :resolved then conversation.update!(status: :resolved)
    when :snoozed then conversation.update!(status: :snoozed, snoozed_until: 3.days.from_now)
    end
  end

  # ---------------------------------------------------------------- notificações
  def seed_notifications
    admin = users[:admin]
    target = Conversation.where(account: account).find_by("additional_attributes ->> 'finture_seed_key' = ?", 'wa-06')
    return unless target
    return if Notification.exists?(user: admin, primary_actor: target)

    Notification.create!(account: account, user: admin, notification_type: :team_assignment, primary_actor: target)
    Notification.create!(account: account, user: users[:ana], notification_type: :team_assignment, primary_actor: target)
  end

  def print_summary
    puts <<~TXT
      [finture-local] Seeds sintéticas aplicadas na conta "#{account.name}" (id #{account.id}).
        Usuários: #{USERS.map { |u| u[2] }.join(', ')}
        Senha: definida em LOCAL_SEED_PASSWORD (.env.local)
        Caixas: #{inboxes.values.map(&:name).join(' | ')}
        Conversas sintéticas: #{Conversation.where(account: account).where("additional_attributes ? 'finture_seed_key'").count}
    TXT
  end
end
