# CRUD das etapas do funil do Kanban SDR, por caixa (inbox_id em params). Leitura
# liberada a agentes (o board precisa das colunas); criar/editar/reordenar/
# remover é restrito a administradores. A etapa travada (Lead Identificado) não
# pode ser removida; renomear altera só o rótulo (o slug é imutável). Excluir uma
# etapa com cards é bloqueado para não orfanar leads.
class Api::V1::Accounts::FinturePipelineStagesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, except: [:index]
  before_action :set_inbox
  before_action :set_stage, only: [:update, :destroy]

  def index
    Finture::PipelineStage.seed_defaults!(@inbox) unless scoped_stages.exists?
    render json: { payload: scoped_stages.map { |stage| serialize(stage) } }
  end

  def create
    stage = Finture::PipelineStage.create!(
      account_id: Current.account.id,
      inbox_id: @inbox.id,
      name: stage_params[:name],
      color: color_param,
      slug: unique_slug(stage_params[:name]),
      position: next_position,
      locked: false
    )
    render json: { stage: serialize(stage) }
  end

  def update
    @stage.update!(name: stage_params[:name].presence || @stage.name, color: color_param)
    render json: { stage: serialize(@stage) }
  end

  def destroy
    return render_error('Não é possível remover a etapa fixa.') if @stage.locked?
    return render_error('Mova os leads desta etapa antes de removê-la.') if stage_has_cards?

    @stage.destroy!
    head :ok
  end

  def reorder
    ordered_ids = Array(params[:order]).map(&:to_i)
    ActiveRecord::Base.transaction do
      # A etapa travada permanece sempre na 1ª posição; o restante segue a ordem.
      locked_ids = scoped_stages.where(locked: true).pluck(:id)
      final = (locked_ids + (ordered_ids - locked_ids)).uniq
      final.each_with_index do |id, index|
        scoped_stages.where(id: id).update_all(position: index)
      end
    end
    render json: { payload: scoped_stages.reload.map { |stage| serialize(stage) } }
  end

  private

  def set_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def scoped_stages
    @scoped_stages ||= Finture::PipelineStage.where(inbox_id: @inbox.id).ordered
  end

  def set_stage
    @stage = scoped_stages.find(params[:id])
  end

  def stage_params
    params.permit(:name, :color)
  end

  def color_param
    Finture::PipelineStage::COLORS.include?(params[:color]) ? params[:color] : (@stage&.color || 'slate')
  end

  def next_position
    (scoped_stages.maximum(:position) || -1) + 1
  end

  # Slug estável e único na caixa, derivado do nome (fallback 'etapa').
  def unique_slug(name)
    base = name.to_s.parameterize(separator: '_').presence || 'etapa'
    slug = base
    counter = 2
    while Finture::PipelineStage.exists?(inbox_id: @inbox.id, slug: slug)
      slug = "#{base}_#{counter}"
      counter += 1
    end
    slug
  end

  def stage_has_cards?
    Current.account.conversations
           .where(inbox_id: @inbox.id)
           .where("custom_attributes ->> 'sdr_stage' = ?", @stage.slug)
           .exists?
  end

  def serialize(stage)
    {
      id: stage.id,
      name: stage.name,
      slug: stage.slug,
      position: stage.position,
      color: stage.color,
      locked: stage.locked
    }
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
