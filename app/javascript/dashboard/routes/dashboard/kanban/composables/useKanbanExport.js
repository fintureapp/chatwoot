// Exportação Excel do Kanban pelo servidor (conjunto filtrado completo, sem o
// cap de 1000 da tela). Compartilhado por board e histórico.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import FintureCrmApi from 'dashboard/api/fintureCrm';
import {
  downloadBlob,
  filenameFromHeaders,
} from 'dashboard/routes/dashboard/kanban/helper/download';

export function useKanbanExport() {
  const { t } = useI18n();
  const isExporting = ref(false);

  // `scope`: board | history; `filters`:
  // chaves já no formato da API (q, product, stage, assignee_id, created_from,
  // created_to, outcome). Valores vazios são removidos.
  const exportCsv = async ({ inboxId, scope, filters = {} }) => {
    if (!inboxId || isExporting.value) return;
    isExporting.value = true;
    try {
      const params = { inbox_id: inboxId, scope };
      Object.entries(filters).forEach(([key, value]) => {
        if (value !== '' && value !== null && value !== undefined) {
          params[key] = value;
        }
      });
      const response = await FintureCrmApi.exportKanban(params);
      downloadBlob(
        response.data,
        filenameFromHeaders(response.headers, `finture-contatos-${scope}.xlsx`)
      );
      useAlert(t('KANBAN.EXPORT.DONE'));
    } catch {
      useAlert(t('KANBAN.EXPORT.ERROR'));
    } finally {
      isExporting.value = false;
    }
  };

  return { isExporting, exportCsv };
}
