import { computed, ref, unref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import FintureCrmApi from 'dashboard/api/fintureCrm';

export const ATTENDANCE_MODES = Object.freeze({ AI: 'ia', HUMAN: 'humano' });

// Modo de atendimento da conversa (IA x humano) — lê `finture_attendance` do
// payload da conversa e executa Assumir / Devolver à IA. O servidor é a fonte
// da verdade: a tela só muda depois da resposta 200 (recarrega a conversa); em
// 409 (alguém agiu antes) mostra quem foi e recarrega o estado real.
export function useFintureAttendance(conversationSource) {
  const store = useStore();
  const { t } = useI18n();
  const isBusy = ref(false);

  const conversation = computed(() => unref(conversationSource) || {});
  const attendance = computed(() => conversation.value.finture_attendance);
  const isEnabled = computed(() => !!attendance.value?.ai_enabled);
  const isAi = computed(
    () => isEnabled.value && attendance.value.mode === ATTENDANCE_MODES.AI
  );
  const isHuman = computed(
    () => isEnabled.value && attendance.value.mode === ATTENDANCE_MODES.HUMAN
  );
  const assignee = computed(() => conversation.value.meta?.assignee);

  const refresh = () =>
    store.dispatch('getConversation', conversation.value.id);

  const handleError = async error => {
    useAlert(
      error?.response?.data?.error || t('CONVERSATION.ATTENDANCE.ERROR')
    );
    if (error?.response?.status === 409) await refresh();
  };

  const run = async (request, successMessage) => {
    if (isBusy.value) return false;
    isBusy.value = true;
    try {
      await request();
      await refresh();
      if (successMessage) useAlert(successMessage);
      return true;
    } catch (error) {
      await handleError(error);
      return false;
    } finally {
      isBusy.value = false;
    }
  };

  // `silent`: usado no "Assumir e enviar" — o envio em seguida já é o retorno.
  const takeOver = ({ silent = false } = {}) =>
    run(
      () =>
        FintureCrmApi.takeOverConversation(conversation.value.id, {
          expectedRevision: attendance.value?.revision,
        }),
      silent ? null : t('CONVERSATION.ATTENDANCE.TAKE_OVER_SUCCESS')
    );

  const returnToAi = ({ reason, pendingNotes }) =>
    run(
      () =>
        FintureCrmApi.returnConversationToAi(conversation.value.id, {
          expectedRevision: attendance.value?.revision,
          reason,
          pendingNotes,
        }),
      t('CONVERSATION.ATTENDANCE.RETURN_SUCCESS')
    );

  return {
    attendance,
    assignee,
    isEnabled,
    isAi,
    isHuman,
    isBusy,
    takeOver,
    returnToAi,
  };
}
