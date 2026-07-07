<script setup>
import Draggable from 'vuedraggable';
import KanbanCard from './KanbanCard.vue';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
  cards: {
    type: Array,
    default: () => [],
  },
  inboxNames: {
    type: Object,
    default: () => ({}),
  },
  // true enquanto QUALQUER card do board está sendo arrastado — usado para
  // destacar as colunas aptas a receber o drop.
  isDragging: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['change', 'drag-start', 'drag-end', 'open']);

const accentClass = {
  slate: 'bg-n-slate-9',
  blue: 'bg-n-blue-9',
  amber: 'bg-n-amber-9',
  teal: 'bg-n-teal-9',
  ruby: 'bg-n-ruby-9',
};

const inboxNameFor = card => props.inboxNames[card.inbox_id] || '';
</script>

<template>
  <div
    class="flex flex-col w-72 shrink-0 rounded-xl bg-n-solid-1 outline -outline-offset-1 max-h-full transition-colors"
    :class="
      isDragging
        ? 'outline-2 outline-dashed outline-n-brand'
        : 'outline-1 outline-n-weak'
    "
  >
    <div class="flex items-center gap-2 px-3 py-3 border-b border-n-weak">
      <span class="size-2 rounded-full" :class="accentClass[stage.color]" />
      <h3 class="text-sm font-medium text-n-slate-12">{{ stage.label }}</h3>
      <span
        class="ml-auto px-1.5 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
      >
        {{ cards.length }}
      </span>
    </div>
    <!-- O Draggable preenche TODA a área da coluna (flex-1 + min-h-full), então o
         espaço vazio abaixo dos cards também funciona como zona de drop. -->
    <div class="flex flex-col flex-1 min-h-0 p-2 overflow-y-auto">
      <Draggable
        :list="cards"
        :group="{ name: 'kanban-sdr' }"
        class="flex flex-col flex-1 min-h-full"
        animation="150"
        ghost-class="kanban-ghost"
        chosen-class="kanban-chosen"
        drag-class="kanban-drag"
        item-key="id"
        @change="emit('change', $event)"
        @start="emit('drag-start')"
        @end="emit('drag-end')"
      >
        <template #item="{ element }">
          <KanbanCard
            :conversation="element"
            :inbox-name="inboxNameFor(element)"
            @open="emit('open', $event)"
          />
        </template>
        <template #footer>
          <p
            v-if="!cards.length"
            class="flex-1 py-6 text-xs text-center text-n-slate-10"
          >
            {{ $t('KANBAN.COLUMN.EMPTY') }}
          </p>
        </template>
      </Draggable>
    </div>
  </div>
</template>

<style scoped lang="scss">
// Placeholder (onde o card vai cair): moldura tracejada clara.
.kanban-ghost {
  @apply opacity-60 bg-n-slate-3 dark:bg-n-slate-9 outline-dashed outline-2 -outline-offset-2 outline-n-brand rounded-xl;
}
// Card de origem enquanto está "pego".
.kanban-chosen {
  @apply cursor-grabbing;
}
// Clone que segue o cursor.
.kanban-drag {
  @apply opacity-90 shadow-lg;
}
</style>
