class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze
  # Coluna do Kanban SDR (custom_attributes.sdr_stage). Não é um custom attribute
  # definido na conta, então é tratada aqui. Conversa sem etapa = '' (o front
  # inclui '' ao filtrar pela 1ª coluna da caixa, onde esses cards aparecem).
  KANBAN_STAGE_KEY = 'sdr_stage'.freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  def perform
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }
    }
  end

  def base_relation
    conversations = @account.conversations.includes(
      :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :messages, :contact_inbox
    )

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account
    ).perform
  end

  def build_condition_query_string(current_filter, query_hash, current_index)
    return super unless query_hash['attribute_key'] == KANBAN_STAGE_KEY

    filter_operator_value = filter_operation(query_hash, current_index)
    "COALESCE(conversations.custom_attributes ->> '#{KANBAN_STAGE_KEY}', '') " \
      "#{filter_operator_value} #{query_hash[:query_operator]}"
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    @conversations.sort_on_last_activity_at.page(current_page)
  end
end
