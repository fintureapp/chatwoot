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
    render json: { kanban_type: Finture::InboxConfig.type_for(@inbox) }
  end

  def update
    kanban_type = params[:kanban_type].to_s
    return render_error('Tipo inválido.') unless Finture::InboxConfig::KANBAN_TYPES.include?(kanban_type)

    config = Finture::InboxConfig.find_or_initialize_by(inbox_id: @inbox.id)
    type_changed = config.new_record? || config.kanban_type != kanban_type
    config.account_id = Current.account.id
    config.kanban_type = kanban_type
    config.save!

    ensure_stages_for_type(kanban_type) if type_changed || stages_missing?
    render json: { kanban_type: config.kanban_type }
  end

  private

  def set_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def stages_missing?
    !Finture::PipelineStage.where(inbox_id: @inbox.id).exists?
  end

  def ensure_stages_for_type(kanban_type)
    Finture::PipelineStage.ensure_stages_for_type!(@inbox, kanban_type)
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
