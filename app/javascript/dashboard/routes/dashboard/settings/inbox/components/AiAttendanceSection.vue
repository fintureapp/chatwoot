<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import FintureCrmApi from 'dashboard/api/fintureCrm';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

// Caixa atendida por IA (triagem do n8n): liga os botões "Assumir conversa" /
// "Devolver à IA" e a volta para a IA quando o cliente reabre a conversa.
// Transcrição de áudio: caixa com IA sempre transcreve (a triagem só entende
// texto); o segundo toggle liga a transcrição em caixas sem IA.
// Persiste em Finture::InboxConfig; só administradores veem e alteram.
const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');

const aiEnabled = ref(false);
const audioTranscriptionEnabled = ref(false);
const isSaving = ref(false);

const applyConfig = data => {
  aiEnabled.value = !!data?.ai_enabled;
  audioTranscriptionEnabled.value = !!data?.audio_transcription_enabled;
};

watch(
  () => props.inbox?.id,
  async inboxId => {
    if (!inboxId || !isAdmin.value) return;
    try {
      const { data } = await FintureCrmApi.getInboxConfig(inboxId);
      applyConfig(data);
    } catch {
      applyConfig(null);
    }
  },
  { immediate: true }
);

const save = async (field, value, request) => {
  const previous = field.value;
  field.value = value;
  isSaving.value = true;
  try {
    const { data } = await request(props.inbox.id, value);
    applyConfig(data);
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch {
    field.value = previous;
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isSaving.value = false;
  }
};

const onToggle = value =>
  save(
    aiEnabled,
    value,
    FintureCrmApi.updateInboxAiEnabled.bind(FintureCrmApi)
  );

const onToggleAudio = value =>
  save(
    audioTranscriptionEnabled,
    value,
    FintureCrmApi.updateInboxAudioTranscription.bind(FintureCrmApi)
  );
</script>

<template>
  <SettingsFieldSection
    v-if="isAdmin"
    :label="$t('INBOX_MGMT.AI_ATTENDANCE.LABEL')"
    :help-text="$t('INBOX_MGMT.AI_ATTENDANCE.HELP_TEXT')"
  >
    <ToggleSwitch
      :model-value="aiEnabled"
      :disabled="isSaving"
      @update:model-value="onToggle"
    />
  </SettingsFieldSection>
  <SettingsFieldSection
    v-if="isAdmin"
    :label="$t('INBOX_MGMT.AUDIO_TRANSCRIPTION.LABEL')"
    :help-text="$t('INBOX_MGMT.AUDIO_TRANSCRIPTION.HELP_TEXT')"
  >
    <ToggleSwitch
      :model-value="aiEnabled || audioTranscriptionEnabled"
      :disabled="isSaving || aiEnabled"
      @update:model-value="onToggleAudio"
    />
  </SettingsFieldSection>
</template>
