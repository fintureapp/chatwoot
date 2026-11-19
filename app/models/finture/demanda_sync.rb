# Estado do envio de uma conversa como demanda à Central de Demandas do HUB
# Finture. Escrito pelo Finture::DemandaSyncService (envio) e pelo
# Finture::DemandaListener (criação no instante em que a conversa fica
# elegível, com `elegivel_em`). Uma linha por conversa; a existência da linha
# significa "esta conversa já virou (ou está virando) demanda", e a partir daí
# toda mudança relevante é reenviada como `updated`.
#
#   pending    criada, ainda sem resposta do HUB
#   synced     último envio aplicado pelo HUB (ou já registrado lá: `duplicado`)
#   retrying   último envio falhou por erro passageiro (o job tenta de novo)
#   divergent  o HUB respondeu 2xx mas NÃO aplicou (`motivo` futuro/atrasado):
#              o estado atual da conversa ainda não está lá
#   failed     HUB recusou (4xx) ou as tentativas acabaram
#
# `recovery_state` acompanha um envio não aplicado (divergent) até ele ser
# superado por um envio aplicado: pending → recovered, ou failed se a
# tentativa seguinte falhar de vez. A reconciliação
# (Finture::DemandaReconcileService) reenvia o que estiver failed/divergent.
class Finture::DemandaSync < ApplicationRecord
  self.table_name = 'finture_demanda_syncs'

  STATUSES = %w[pending synced retrying divergent failed].freeze
  RECOVERY_STATES = %w[pending recovered failed].freeze
  OPEN_RECOVERY = %w[pending failed].freeze

  belongs_to :account
  belongs_to :conversation

  validates :external_id, presence: true, uniqueness: true
  validates :conversation_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :recovery_state, inclusion: { in: RECOVERY_STATES }, allow_nil: true

  scope :awaiting_recovery, -> { where(recovery_state: OPEN_RECOVERY) }

  # Cria a linha da conversa no instante em que ela ficou elegível, gravando
  # esse instante como `elegivel_em`. Linha já existente não é tocada: o
  # `elegivel_em` é fixo por demanda e nunca é preenchido depois (seria uma
  # aproximação). Devolve a linha criada ou nil.
  def self.open_for_eligibility!(conversation, eligible_at)
    return if exists?(conversation_id: conversation.id)

    create!(account_id: conversation.account_id, conversation: conversation, inbox_id: conversation.inbox_id,
            external_id: Finture::DemandaSyncService.external_id(conversation), elegivel_em: eligible_at)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def synced?
    status == 'synced'
  end

  # Falha definitiva (4xx ou tentativas esgotadas). Uma recuperação em aberto
  # passa a `failed`, para a reconciliação tentar de novo.
  def mark_failed!(message)
    update!(status: 'failed', last_error: message.to_s.truncate(1000),
            recovery_state: recovery_state == 'pending' ? 'failed' : recovery_state)
  end
end
