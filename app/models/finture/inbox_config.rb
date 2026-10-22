# Classificação de negócio de uma caixa (inbox) no Kanban SDR. Determina o funil
# semeado, a mecânica de saída do board e a visão padrão do Dashboard.
#   - 'comercial'  (default): funil de vendas; card sai por desfecho (ganho/perdido).
#   - 'operacional': funil de atendimento; card sai ao resolver a conversa (status
#     resolved) — o resumo por IA é gerado no fluxo n8n disparado pelo resolve.
# Sem linha para a caixa => 'comercial' (preserva o comportamento anterior).
#
# `ai_enabled`: caixa atendida por IA (triagem do n8n). Liga os controles
# Assumir/Devolver e a volta para a IA quando o cliente reabre a conversa.
class Finture::InboxConfig < ApplicationRecord
  self.table_name = 'finture_inbox_configs'

  KANBAN_TYPES = %w[comercial operacional].freeze
  DEFAULT_TYPE = 'comercial'.freeze

  belongs_to :account
  belongs_to :inbox

  validates :kanban_type, inclusion: { in: KANBAN_TYPES }
  validates :inbox_id, uniqueness: true

  # Tipo efetivo da caixa (default 'comercial' quando não configurada).
  def self.type_for(inbox)
    find_by(inbox_id: inbox.id)&.kanban_type || DEFAULT_TYPE
  end

  def self.operational?(inbox)
    type_for(inbox) == 'operacional'
  end

  def self.ai_enabled?(inbox_id)
    exists?(inbox_id: inbox_id, ai_enabled: true)
  end

  # {inbox_id => true} das caixas com IA, para payloads em lote (kanban).
  def self.ai_enabled_map(inbox_ids)
    where(inbox_id: inbox_ids, ai_enabled: true).pluck(:inbox_id).index_with(true)
  end
end
