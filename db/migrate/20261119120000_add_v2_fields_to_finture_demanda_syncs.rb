# Central de Demandas, etapa E (payload v2 e reconciliação). Só acrescenta
# colunas a finture_demanda_syncs; nada é apagado nem renomeado, então a imagem
# anterior (v1) continua lendo e gravando a tabela.
#
#   sequencia       último número de sequência enviado ao HUB (monotônico por conversa)
#   attempt_hash    SHA-256 do último corpo enviado sem a sequência: a retentativa
#                   do MESMO envio reaproveita o número, e o HUB deduplica
#   elegivel_em     instante registrado em que a conversa virou demanda
#                   (caixa operacional + em_atendimento + responsável); null = desconhecido
#   hub_motivo      `motivo` da última resposta do HUB (futuro, atrasado, duplicado ou null)
#   recovery_state  pending | recovered | failed: recuperação de um envio que o HUB
#                   recebeu e não aplicou (futuro/atrasado)
#   rejected_at     quando o HUB respondeu pela última vez sem aplicar
#   recovered_at    quando um envio posterior foi aplicado e encerrou a recuperação
class AddV2FieldsToFintureDemandaSyncs < ActiveRecord::Migration[7.1]
  def change
    change_table :finture_demanda_syncs, bulk: true do |t|
      t.integer :sequencia, null: false, default: 0
      t.string :attempt_hash
      t.datetime :elegivel_em
      t.string :hub_motivo
      t.string :recovery_state
      t.datetime :rejected_at
      t.datetime :recovered_at
    end
  end
end
