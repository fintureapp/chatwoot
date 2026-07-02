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
});

const emit = defineEmits(['change']);

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
    class="flex flex-col w-72 shrink-0 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak max-h-full"
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
    <div class="flex-1 p-2 overflow-y-auto">
      <Draggable
        :list="cards"
        :group="{ name: 'kanban-sdr' }"
        class="flex flex-col min-h-[6rem]"
        animation="150"
        ghost-class="kanban-ghost"
        item-key="id"
        @change="emit('change', $event)"
      >
        <template #item="{ element }">
          <KanbanCard
            :conversation="element"
            :inbox-name="inboxNameFor(element)"
          />
        </template>
        <template #footer>
          <p
            v-if="!cards.length"
            class="py-6 text-xs text-center text-n-slate-10"
          >
            {{ $t('KANBAN.COLUMN.EMPTY') }}
          </p>
        </template>
      </Draggable>
    </div>
  </div>
</template>

<style scoped lang="scss">
.kanban-ghost {
  @apply opacity-50 bg-n-slate-3 dark:bg-n-slate-9;
}
</style>
