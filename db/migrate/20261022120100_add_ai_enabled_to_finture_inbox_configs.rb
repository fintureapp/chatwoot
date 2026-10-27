# Marca as caixas atendidas por IA (fluxos de triagem do n8n). Só nelas aparecem
# os controles "Assumir conversa" / "Devolver à IA" e só nelas a conversa
# reaberta pelo cliente volta para a IA.
class AddAiEnabledToFintureInboxConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :finture_inbox_configs, :ai_enabled, :boolean, null: false, default: false
  end
end
