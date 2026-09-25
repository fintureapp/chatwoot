<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';

// Classificação de negócio da caixa (comercial/operacional) do Kanban SDR.
// Persiste via endpoint próprio (Finture::InboxConfig) — não passa pelo update
// padrão da inbox. Visível só para administradores (o backend também restringe).
const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
});

const store = useStore();
const { t } = useI18n();
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');

const isSaving = ref(false);

const kanbanType = computed(() =>
  store.getters['kanban/getInboxType'](props.inbox?.id)
);

const options = computed(() => [
  { value: 'comercial', label: t('INBOX_MGMT.KANBAN_CLASSIFICATION.COMMERCIAL') },
  {
    value: 'operacional',
    label: t('INBOX_MGMT.KANBAN_CLASSIFICATION.OPERATIONAL'),
  },
]);

watch(
  () => props.inbox?.id,
  inboxId => {
    if (inboxId) store.dispatch('kanban/fetchInboxConfig', { inboxId });
  },
  { immediate: true }
);

const onChange = async value => {
  isSaving.value = true;
  try {
    await store.dispatch('kanban/updateInboxConfig', {
      inboxId: props.inbox.id,
      kanbanType: value,
    });
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <SettingsFieldSection
    v-if="isAdmin"
    :label="$t('INBOX_MGMT.KANBAN_CLASSIFICATION.LABEL')"
    :help-text="$t('INBOX_MGMT.KANBAN_CLASSIFICATION.HELP_TEXT')"
  >
    <SelectInput
      :model-value="kanbanType"
      :options="options"
      :disabled="isSaving"
      @update:model-value="onChange"
    />
  </SettingsFieldSection>
</template>
