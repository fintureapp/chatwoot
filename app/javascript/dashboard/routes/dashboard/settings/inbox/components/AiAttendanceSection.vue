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
// Persiste em Finture::InboxConfig; só administradores veem e alteram.
const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');

const aiEnabled = ref(false);
const isSaving = ref(false);

watch(
  () => props.inbox?.id,
  async inboxId => {
    if (!inboxId || !isAdmin.value) return;
    try {
      const { data } = await FintureCrmApi.getInboxConfig(inboxId);
      aiEnabled.value = !!data?.ai_enabled;
    } catch {
      aiEnabled.value = false;
    }
  },
  { immediate: true }
);

const onToggle = async value => {
  const previous = aiEnabled.value;
  aiEnabled.value = value;
  isSaving.value = true;
  try {
    const { data } = await FintureCrmApi.updateInboxAiEnabled(
      props.inbox.id,
      value
    );
    aiEnabled.value = !!data?.ai_enabled;
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch {
    aiEnabled.value = previous;
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isSaving.value = false;
  }
};
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
</template>
