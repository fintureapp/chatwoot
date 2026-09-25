# Classificação de negócio da caixa (comercial/operacional) do Kanban SDR.
# Leitura liberada a agentes (o board/dashboard precisam do tipo); alterar é
# restrito a administradores. Ao definir o tipo, semeia o funil padrão daquele
# tipo caso a caixa ainda não tenha etapas — assim uma caixa operacional nova já
# nasce com "Chamada Iniciada → Em Triagem → Em Atendimento". Se a caixa já tem
# funil configurado, o tipo muda sem mexer nas colunas (use o gerenciador de
# etapas para ajustá-las).
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
    config.account_id = Current.account.id
    config.kanban_type = kanban_type
    config.save!

    seed_stages_for_type(kanban_type)
    render json: { kanban_type: config.kanban_type }
  end

  private

  def set_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def seed_stages_for_type(kanban_type)
    return if Finture::PipelineStage.where(inbox_id: @inbox.id).exists?

    Finture::PipelineStage.seed_defaults!(@inbox, kanban_type)
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
