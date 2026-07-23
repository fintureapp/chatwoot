<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { resolveStage } from 'dashboard/routes/dashboard/kanban/config/stages';

import KanbanColumn from './KanbanColumn.vue';
import KanbanCardDrawer from './KanbanCardDrawer.vue';
import LostReasonDialog from './LostReasonDialog.vue';

const props = defineProps({
  // Registros já filtrados/ordenados pela toolbar da página.
  records: {
    type: Array,
    default: () => [],
  },
  // Etapas da caixa ativa (Fase B): [{ id, name, slug, color, position, locked }].
  stages: {
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

// Desfecho (ganho/perdido) marcado dentro do card.
const lostDialogRef = ref(null);
const pendingLost = ref(null);

// Estado do drawer de detalhe.
const selectedConversationId = ref(null);
const drawerIntent = ref('detail');
const isDrawerOpen = ref(false);

const stageSlugs = computed(() => props.stages.map(stage => stage.slug));

const rebuildColumns = () => {
  const slugs = stageSlugs.value;
  localColumns.value = props.stages.map(stage => ({
    stage: { value: stage.slug, label: stage.name, color: stage.color },
    cards: props.records.filter(
      record => resolveStage(record, slugs) === stage.slug
    ),
  }));
};

// Reconstrói quando as etapas OU o conjunto/ordem de registros mudam (fetch,
// filtro, ordenação, reconfiguração de etapas, desfecho), nunca em atualização
// de atributo em memória — evita "piscar" o card após o drop.
const columnsSignature = computed(
  () =>
    `${stageSlugs.value.join(',')}|${props.records
      .map(record => record.id)
      .join(',')}`
);
watch(columnsSignature, rebuildColumns, { immediate: true });

const persistStage = async (conversation, stage) => {
  try {
    await store.dispatch('kanban/changeStage', {
      conversationId: conversation.id,
      stage,
    });
  } catch {
    rebuildColumns();
    useAlert(t('KANBAN.ERRORS.UPDATE_STAGE'));
  }
};

const handleChange = (stageValue, event) => {
  // Só reagimos ao card que ENTRA numa coluna (destino).
  if (!event.added) return;
  persistStage(event.added.element, stageValue);
};

const markOutcome = async (conversation, kind, extra = {}) => {
  try {
    await store.dispatch('kanban/markOutcome', {
      conversationId: conversation.id,
      kind,
      ...extra,
    });
  } catch {
    useAlert(t('KANBAN.ERRORS.UPDATE_OUTCOME'));
  }
};

const onWon = conversation => markOutcome(conversation, 'won');

const onLost = conversation => {
  pendingLost.value = conversation;
  lostDialogRef.value.open();
};

const onLostSubmit = ({ reason, comment }) => {
  const conversation = pendingLost.value;
  pendingLost.value = null;
  markOutcome(conversation, 'lost', { reason, comment });
};

const onLostCancel = () => {
  pendingLost.value = null;
};

const openDrawer = ({ conversation, intent }) => {
  selectedConversationId.value = conversation.id;
  drawerIntent.value = intent || 'detail';
  isDrawerOpen.value = true;
};
</script>

<template>
  <div class="flex flex-col min-h-0">
    <div class="flex flex-1 gap-3 px-3 py-3 overflow-x-auto min-h-0">
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
        @won="onWon"
        @lost="onLost"
      />
    </div>

    <LostReasonDialog
      ref="lostDialogRef"
      @submit="onLostSubmit"
      @cancel="onLostCancel"
    />

    <KanbanCardDrawer
      v-model:open="isDrawerOpen"
      :conversation-id="selectedConversationId"
      :intent="drawerIntent"
      :inbox-names="inboxNames"
    />
  </div>
</template>
