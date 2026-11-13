# Estado do envio de uma conversa como demanda à Central de Demandas do HUB
# Finture. Escrito só pelo Finture::DemandaSyncService. Uma linha por conversa;
# a existência da linha significa "esta conversa já virou (ou está virando)
# demanda", e a partir daí toda mudança relevante é reenviada como `updated`.
#
#   pending   criada, ainda sem resposta do HUB
#   synced    último envio aceito pelo HUB
#   retrying  último envio falhou por erro passageiro (o job tenta de novo)
#   failed    HUB recusou (4xx) ou as tentativas acabaram; exige ação humana
class Finture::DemandaSync < ApplicationRecord
  self.table_name = 'finture_demanda_syncs'

  STATUSES = %w[pending synced retrying failed].freeze

  belongs_to :account
  belongs_to :conversation

  validates :external_id, presence: true, uniqueness: true
  validates :conversation_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  def synced?
    status == 'synced'
  end
end
