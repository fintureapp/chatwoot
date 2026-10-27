# Dados da exportação do Kanban: aplica os filtros do board/histórico sobre o
# escopo (sem o cap de 1000) e monta UMA linha por CONTATO, deduplicado por id
# do contato (sem id, pelo telefone só com dígitos; sem telefone, pelo e-mail).
# O contexto (etapa, responsável, produto, desfecho…) vem da demanda mais
# recente; as demais ficam contadas e listadas — nada é perdido.
class Finture::KanbanExportDataset
  NOT_INFORMED = 'Não informado'.freeze
  TIMEZONE = 'America/Sao_Paulo'.freeze

  LOST_REASONS = {
    'sem_resposta' => 'Sem resposta', 'sem_interesse' => 'Não tinha interesse', 'fora_do_perfil' => 'Fora do perfil',
    'contato_invalido' => 'Contato inválido', 'ja_contratou_outro' => 'Já contratou com outro fornecedor',
    'preco_condicao' => 'Preço/condição', 'produto_nao_aderente' => 'Produto não aderente', 'timing_ruim' => 'Timing ruim',
    'duplicado' => 'Duplicado', 'indicacao_incorreta' => 'Indicação incorreta', 'outro' => 'Outro'
  }.freeze

  # scope: conversas já recortadas por board/histórico e permissão (sem limit).
  # params: q, product, stage, assignee_id, created_from, created_to.
  pattr_initialize [:scope!, :params!, :inbox!, :kanban_type!]

  # Linhas na ordem das colunas de Finture::KanbanExportService::COLUMNS.
  def rows
    @rows ||= begin
      groups = records.group_by { |c| contact_key(c) }.values
      groups.sort_by { |group| -group.map { |c| activity_at(c) }.max }.map do |group|
        sorted = group.sort_by { |c| -activity_at(c) }
        contact_row(sorted.first, sorted)
      end
    end
  end

  def records
    @records ||= filtered_scope.includes(:contact, :assignee).to_a
  end

  def stage_label(slug)
    stage = stages.find { |s| s.slug == slug } || stages.first
    stage&.name || slug.presence || NOT_INFORMED
  end

  private

  def contact_row(latest, group) # rubocop:disable Metrics/AbcSize
    attrs = latest.custom_attributes || {}
    contact = latest.contact
    [
      informed(contact&.name), informed(contact&.phone_number), informed(contact&.email),
      informed(latest.assignee&.available_name), informed(attrs['produto_interesse']), stage_label(attrs['sdr_stage']),
      outcome_label(latest), lost_reason(latest), volume(attrs['valor_potencial']), attrs['sdr_next_action'].to_s,
      group.size, group.map(&:display_id).join(', '), local(group.filter_map(&:created_at).min),
      local(latest.last_activity_at), closed_at(latest), contact&.id
    ]
  end

  def activity_at(conversation)
    (conversation.last_activity_at || conversation.created_at).to_i
  end

  # ---- Filtros --------------------------------------------------------------

  def filtered_scope # rubocop:disable Metrics/AbcSize
    result = apply_query(scope)
    result = result.where("conversations.custom_attributes ->> 'produto_interesse' = ?", params[:product]) if params[:product].present?
    result = result.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    result = apply_stage(result)
    result = result.where('conversations.created_at >= ?', day_start(params[:created_from])) if params[:created_from].present?
    result = result.where('conversations.created_at <= ?', day_end(params[:created_to])) if params[:created_to].present?
    result
  end

  # Mesmo critério da busca do board: nome, telefone, e-mail ou produto.
  def apply_query(result)
    query = params[:q].to_s.strip
    return result if query.blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    conditions = ['contacts.name ILIKE :term', 'contacts.email ILIKE :term', 'contacts.phone_number ILIKE :term',
                  "conversations.custom_attributes ->> 'produto_interesse' ILIKE :term"]
    result.joins(:contact).where(conditions.join(' OR '), term: term)
  end

  # Etapa desconhecida/ausente conta como a 1ª etapa (mesma regra do board).
  def apply_stage(result)
    stage = params[:stage].to_s
    return result if stage.blank?
    return result.where("conversations.custom_attributes ->> 'sdr_stage' = ?", stage) unless stage == stages.first&.slug

    known = stages.map(&:slug)
    result.where(
      "conversations.custom_attributes ->> 'sdr_stage' IS NULL OR conversations.custom_attributes ->> 'sdr_stage' NOT IN (?) " \
      "OR conversations.custom_attributes ->> 'sdr_stage' = ?", known, stage
    )
  end

  def stages
    @stages ||= Finture::PipelineStage.where(inbox_id: inbox.id).ordered.to_a
  end

  def contact_key(conversation)
    contact = conversation.contact
    return "contact:#{contact.id}" if contact&.id

    digits = contact&.phone_number.to_s.gsub(/\D/, '')
    return "phone:#{digits}" if digits.present?
    return "email:#{contact.email.downcase}" if contact&.email.present?

    "conv:#{conversation.id}"
  end

  # ---- Rótulos / formatos ---------------------------------------------------

  def informed(value)
    value.presence || NOT_INFORMED
  end

  def outcome_label(conversation)
    outcome = conversation.custom_attributes&.dig('sdr_outcome')
    return 'Ganho' if outcome == 'won'
    return 'Perdido' if outcome == 'lost'
    return 'Resolvida' if kanban_type == 'operacional' && conversation.status == 'resolved'

    'Em aberto'
  end

  def lost_reason(conversation)
    attrs = conversation.custom_attributes || {}
    return '' unless attrs['sdr_outcome'] == 'lost'

    LOST_REASONS[attrs['sdr_lost_reason']] || attrs['sdr_lost_reason'].to_s
  end

  def closed_at(conversation)
    attrs = conversation.custom_attributes || {}
    return local(Time.zone.at(attrs['sdr_outcome_at'].to_i)) if attrs['sdr_outcome_at'].present?
    return local(conversation.last_activity_at) if kanban_type == 'operacional' && conversation.status == 'resolved'

    nil
  end

  def volume(raw)
    return nil if raw.blank?

    Float(raw, exception: false)
  end

  # Excel não guarda fuso: gravamos a hora de parede de Brasília.
  def local(time)
    time.presence&.in_time_zone(TIMEZONE)
  end

  def day_start(date)
    ActiveSupport::TimeZone[TIMEZONE].parse(date.to_s).beginning_of_day
  end

  def day_end(date)
    ActiveSupport::TimeZone[TIMEZONE].parse(date.to_s).end_of_day
  end
end
