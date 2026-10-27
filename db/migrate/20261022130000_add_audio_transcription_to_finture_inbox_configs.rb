# Transcrição automática dos áudios recebidos na caixa (Finture::AudioTranscriptionJob).
# Caixa com IA (ai_enabled) já transcreve; este campo liga a transcrição também em
# caixas atendidas só por humanos.
class AddAudioTranscriptionToFintureInboxConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :finture_inbox_configs, :audio_transcription_enabled, :boolean, null: false, default: false
  end
end
