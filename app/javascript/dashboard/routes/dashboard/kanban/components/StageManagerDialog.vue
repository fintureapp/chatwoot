<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// Gerenciador das etapas do funil da caixa ativa (admin). A etapa travada
// (Lead Identificado) fica sempre no topo, sem reordenar/remover. As demais
// podem ser adicionadas, renomeadas, recoloridas e reordenadas (drag). Cada
// ação persiste no backend (finture_pipeline_stages) e re-sincroniza.
const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
  stages: {
    type: Array,
    default: () => [],
  },
});

const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const lockedStages = ref([]);
const draggableStages = ref([]);
const newName = ref('');

const COLORS = ['slate', 'blue', 'teal', 'amber', 'ruby'];
const colorClass = {
  slate: 'bg-n-slate-9',
  blue: 'bg-n-blue-9',
  teal: 'bg-n-teal-9',
  amber: 'bg-n-amber-9',
  ruby: 'bg-n-ruby-9',
};

const syncFromProps = () => {
  lockedStages.value = props.stages
    .filter(stage => stage.locked)
    .map(stage => ({ ...stage }));
  draggableStages.value = props.stages
    .filter(stage => !stage.locked)
    .map(stage => ({ ...stage }));
};

const open = () => {
  syncFromProps();
  dialogRef.value?.open();
};
const close = () => dialogRef.value?.close();
defineExpose({ open, close });

// Sempre re-sincroniza da verdade do servidor (o store refetcha após a ação).
const runAction = async (action, payload) => {
  try {
    await store.dispatch(action, payload);
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('KANBAN.STAGE_MANAGER.SAVE_ERROR')
    );
  } finally {
    syncFromProps();
  }
};

const renameStage = stage =>
  runAction('kanban/updateStageConfig', {
    inboxId: props.inboxId,
    stageId: stage.id,
    changes: { name: stage.name },
  });

const recolorStage = (stage, color) => {
  stage.color = color;
  runAction('kanban/updateStageConfig', {
    inboxId: props.inboxId,
    stageId: stage.id,
    changes: { color },
  });
};

const removeStage = stage =>
  runAction('kanban/deleteStage', {
    inboxId: props.inboxId,
    stageId: stage.id,
  });

const onReorder = () => {
  const order = [
    ...lockedStages.value.map(stage => stage.id),
    ...draggableStages.value.map(stage => stage.id),
  ];
  runAction('kanban/reorderStages', { inboxId: props.inboxId, order });
};

const addStage = async () => {
  const name = newName.value.trim();
  if (!name) return;
  await runAction('kanban/createStage', {
    inboxId: props.inboxId,
    stage: { name, color: 'slate' },
  });
  newName.value = '';
};

const inputClass =
  'flex-1 h-8 px-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('KANBAN.STAGE_MANAGER.TITLE')"
    :description="t('KANBAN.STAGE_MANAGER.SUBTITLE')"
    :show-confirm-button="false"
    :cancel-button-label="t('KANBAN.STAGE_MANAGER.CLOSE')"
    width="md"
  >
    <div class="flex flex-col gap-2">
      <!-- Etapa fixa (Lead Identificado) -->
      <div
        v-for="stage in lockedStages"
        :key="stage.id"
        class="flex items-center gap-2 p-2 rounded-lg bg-n-alpha-1"
      >
        <Icon icon="i-lucide-lock" class="size-4 text-n-slate-10" />
        <span class="rounded-full size-2.5" :class="colorClass[stage.color]" />
        <span class="flex-1 text-sm text-n-slate-12">{{ stage.name }}</span>
        <span class="text-xs text-n-slate-10">
          {{ t('KANBAN.STAGE_MANAGER.FIXED') }}
        </span>
      </div>

      <!-- Etapas customizáveis (arraste para reordenar) -->
      <Draggable
        :list="draggableStages"
        item-key="id"
        handle=".drag-handle"
        animation="150"
        class="flex flex-col gap-2"
        @end="onReorder"
      >
        <template #item="{ element: stage }">
          <div class="flex items-center gap-2 p-2 rounded-lg bg-n-alpha-1">
            <button
              type="button"
              class="drag-handle cursor-grab text-n-slate-10 hover:text-n-slate-11"
            >
              <Icon icon="i-lucide-grip-vertical" class="size-4" />
            </button>
            <div class="flex items-center gap-1">
              <button
                v-for="color in COLORS"
                :key="color"
                type="button"
                class="rounded-full size-4"
                :class="[
                  colorClass[color],
                  stage.color === color
                    ? 'ring-2 ring-offset-1 ring-n-slate-9 ring-offset-n-alpha-3'
                    : '',
                ]"
                @click="recolorStage(stage, color)"
              />
            </div>
            <input
              v-model="stage.name"
              :class="inputClass"
              @change="renameStage(stage)"
            />
            <button
              type="button"
              class="text-n-slate-10 hover:text-n-ruby-11"
              @click="removeStage(stage)"
            >
              <Icon icon="i-lucide-trash-2" class="size-4" />
            </button>
          </div>
        </template>
      </Draggable>

      <!-- Adicionar etapa -->
      <div class="flex items-center gap-2 pt-3 mt-1 border-t border-n-weak">
        <input
          v-model="newName"
          :placeholder="t('KANBAN.STAGE_MANAGER.NEW_PLACEHOLDER')"
          :class="inputClass"
          @keydown.enter.prevent="addStage"
        />
        <Button
          color="blue"
          size="sm"
          icon="i-lucide-plus"
          :label="t('KANBAN.STAGE_MANAGER.ADD')"
          :disabled="!newName.trim()"
          @click="addStage"
        />
      </div>
    </div>
  </Dialog>
</template>
