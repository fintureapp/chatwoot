<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// Botão de exportação (board e histórico): gera no servidor um Excel com
// identidade Finture, uma linha por contato, sobre o recorte filtrado completo.
defineProps({
  hasActiveFilters: {
    type: Boolean,
    default: false,
  },
  isExporting: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['export']);
const { t } = useI18n();
</script>

<template>
  <Button
    v-tooltip.bottom="
      hasActiveFilters
        ? t('KANBAN.EXPORT.SCOPE_FILTERED')
        : t('KANBAN.EXPORT.SCOPE_ALL')
    "
    color="slate"
    variant="outline"
    size="sm"
    icon="i-lucide-file-spreadsheet"
    :label="t('KANBAN.EXPORT.BUTTON')"
    :is-loading="isExporting"
    :disabled="isExporting"
    @click="emit('export')"
  />
</template>
