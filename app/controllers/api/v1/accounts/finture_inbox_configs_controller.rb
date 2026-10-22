# Classificação de negócio da caixa (comercial/operacional) do Kanban SDR.
# Leitura liberada a agentes (o board/dashboard precisam do tipo); alterar é
# restrito a administradores. Ao mudar o tipo, garante o funil padrão daquele
# tipo na caixa (Finture::PipelineStage.ensure_stages_for_type!): caixa sem
# etapas nasce com o funil completo; caixa que já tem etapas ganha o rótulo da
# etapa travada e as etapas padrão que faltam, sem perder colunas nem cards.
class Api::V1::Accounts::FintureInboxConfigsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, only: [:update]
  before_action :set_inbox

  def show
    render json: { kanban_type: Finture::InboxConfig.type_for(@inbox), ai_enabled: Finture::InboxConfig.ai_enabled?(@inbox.id) }
  end

  # Aceita `kanban_type` e/ou `ai_enabled` (o que não vier fica como está).
  def update
    kanban_type = params[:kanban_type].presence&.to_s
    return render_error('Tipo inválido.') if kanban_type && Finture::InboxConfig::KANBAN_TYPES.exclude?(kanban_type)

    config = Finture::InboxConfig.find_or_initialize_by(inbox_id: @inbox.id)
    type_changed = type_changing?(config, kanban_type)
    assign_config(config, kanban_type)
    config.save!

    ensure_stages_for_type(config.kanban_type) if type_changed || (kanban_type && stages_missing?)
    render json: { kanban_type: config.kanban_type, ai_enabled: config.ai_enabled }
  end

  private

  def type_changing?(config, kanban_type)
    return false if kanban_type.blank?

    config.new_record? || config.kanban_type != kanban_type
  end

  def assign_config(config, kanban_type)
    config.account_id = Current.account.id
    config.kanban_type = kanban_type if kanban_type
    config.ai_enabled = ActiveModel::Type::Boolean.new.cast(params[:ai_enabled]) if params.key?(:ai_enabled)
  end

  def set_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def stages_missing?
    !Finture::PipelineStage.exists?(inbox_id: @inbox.id)
  end

  def ensure_stages_for_type(kanban_type)
    Finture::PipelineStage.ensure_stages_for_type!(@inbox, kanban_type)
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
