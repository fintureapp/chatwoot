<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  KANBAN_STAGES,
  WON_STAGE,
  LOST_STAGE,
  resolveStage,
} from 'dashboard/routes/dashboard/kanban/config/stages';

import KanbanColumn from './KanbanColumn.vue';
import LostReasonDialog from './LostReasonDialog.vue';
import KanbanCardDrawer from './KanbanCardDrawer.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  // Registros já filtrados/ordenados pela toolbar da página.
  records: {
    type: Array,
    default: () => [],
  },
  inboxNames: {
    type: Object,
    default: () => ({}),
  },
});

const store = useStore();
const { t } = useI18n();

const localColumns = ref([]);
const isDragging = ref(false);

const lostDialogRef = ref(null);
const wonDialogRef = ref(null);
const pendingLost = ref(null);
const pendingWon = ref(null);
const wonConfirmed = ref(false);

// Estado do drawer de detalhe.
const selectedConversationId = ref(null);
const drawerIntent = ref('detail');
const isDrawerOpen = ref(false);

const rebuildColumns = () => {
  localColumns.value = KANBAN_STAGES.map(stage => ({
    stage,
    cards: props.records.filter(record => resolveStage(record) === stage.value),
  }));
};

// Reconstrói apenas quando o conjunto/ordem de registros muda (fetch, filtro,
// ordenação), nunca em atualização de atributo em memória — evita "piscar" o card
// após o drop (o SortableJS já moveu o DOM).
const columnsSignature = computed(() =>
  props.records.map(record => record.id).join(',')
);
watch(columnsSignature, rebuildColumns, { immediate: true });

const persistStage = async (conversation, stage, extra = {}) => {
  try {
    await store.dispatch('kanban/updateStage', {
      conversationId: conversation.id,
      stage,
      ...extra,
    });
  } catch {
    rebuildColumns();
    useAlert(t('KANBAN.ERRORS.UPDATE_STAGE'));
  }
};

const handleChange = (stageValue, event) => {
  // Só reagimos ao card que ENTRA numa coluna (destino).
  if (!event.added) return;
  const conversation = event.added.element;

  if (stageValue === LOST_STAGE) {
    pendingLost.value = conversation;
    lostDialogRef.value.open();
    return;
  }
  if (stageValue === WON_STAGE) {
    pendingWon.value = conversation;
    wonConfirmed.value = false;
    wonDialogRef.value.open();
    return;
  }
  persistStage(conversation, stageValue);
};

const onLostSubmit = ({ reason, comment }) => {
  const conversation = pendingLost.value;
  pendingLost.value = null;
  persistStage(conversation, LOST_STAGE, {
    lostReason: reason,
    lostComment: comment,
  });
};

const onLostCancel = () => {
  pendingLost.value = null;
  rebuildColumns();
};

const onWonConfirm = () => {
  wonConfirmed.value = true;
  const conversation = pendingWon.value;
  pendingWon.value = null;
  wonDialogRef.value.close();
  persistStage(conversation, WON_STAGE);
};

const onWonClose = () => {
  if (!wonConfirmed.value) rebuildColumns();
};

const openDrawer = ({ conversation, intent }) => {
  selectedConversationId.value = conversation.id;
  drawerIntent.value = intent || 'detail';
  isDrawerOpen.value = true;
};
</script>

<template>
  <div class="flex flex-col min-h-0">
    <div class="flex flex-1 gap-4 px-6 py-4 overflow-x-auto min-h-0">
      <KanbanColumn
        v-for="column in localColumns"
        :key="column.stage.value"
        :stage="column.stage"
        :cards="column.cards"
        :inbox-names="inboxNames"
        :is-dragging="isDragging"
        @change="handleChange(column.stage.value, $event)"
        @drag-start="isDragging = true"
        @drag-end="isDragging = false"
        @open="openDrawer"
      />
    </div>

    <LostReasonDialog
      ref="lostDialogRef"
      @submit="onLostSubmit"
      @cancel="onLostCancel"
    />

    <Dialog
      ref="wonDialogRef"
      type="edit"
      :title="t('KANBAN.WON_DIALOG.TITLE')"
      :description="t('KANBAN.WON_DIALOG.DESCRIPTION')"
      :confirm-button-label="t('KANBAN.WON_DIALOG.CONFIRM')"
      @confirm="onWonConfirm"
      @close="onWonClose"
    />

    <KanbanCardDrawer
      v-model:open="isDrawerOpen"
      :conversation-id="selectedConversationId"
      :intent="drawerIntent"
      :inbox-names="inboxNames"
    />
  </div>
</template>
