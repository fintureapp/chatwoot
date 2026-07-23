<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  filters: {
    type: Object,
    required: true,
  },
  sortBy: {
    type: String,
    default: 'last_activity_desc',
  },
  products: {
    type: Array,
    default: () => [],
  },
  assignees: {
    type: Array,
    default: () => [],
  },
  hasActiveFilters: {
    type: Boolean,
    default: false,
  },
  stages: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:filters', 'update:sort-by', 'clear']);

const { t } = useI18n();

const isPanelOpen = ref(false);

const setFilter = (key, value) => {
  emit('update:filters', { ...props.filters, [key]: value });
};

// A busca fica sempre visível na barra; os demais filtros vivem no popover
// "Filtros". O contador do badge considera só esses filtros avançados.
const ADVANCED_KEYS = [
  'product',
  'stage',
  'assigneeId',
  'createdFrom',
  'createdTo',
];
const activeCount = computed(
  () => ADVANCED_KEYS.filter(key => props.filters[key] !== '').length
);

const inputClass =
  'h-8 px-2.5 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand';
const fieldClass = `w-full ${inputClass}`;
</script>

<template>
  <div class="flex items-center gap-2 px-3 py-2 border-b border-n-weak">
    <!-- Busca textual (cliente / produto) — sempre visível -->
    <div class="relative">
      <Icon
        icon="i-lucide-search"
        class="absolute -translate-y-1/2 size-4 text-n-slate-10 top-1/2 ltr:left-2.5 rtl:right-2.5"
      />
      <input
        :value="filters.query"
        type="search"
        :placeholder="t('KANBAN.TOOLBAR.SEARCH_PLACEHOLDER')"
        :class="inputClass"
        class="w-64 ltr:pl-8 rtl:pr-8"
        @input="setFilter('query', $event.target.value)"
      />
    </div>

    <!-- Filtros avançados em popover -->
    <div v-on-click-outside="() => (isPanelOpen = false)" class="relative">
      <Button
        color="slate"
        variant="outline"
        size="sm"
        icon="i-lucide-sliders-horizontal"
        :label="t('KANBAN.TOOLBAR.FILTERS')"
        @click="isPanelOpen = !isPanelOpen"
      />
      <span
        v-if="activeCount"
        class="absolute flex items-center justify-center h-4 px-1 text-[10px] font-medium text-white rounded-full -top-1 min-w-4 ltr:-right-1 rtl:-left-1 bg-n-brand"
      >
        {{ activeCount }}
      </span>

      <div
        v-if="isPanelOpen"
        class="absolute z-40 flex flex-col gap-3 p-3 mt-1 border rounded-lg shadow-lg ltr:left-0 rtl:right-0 top-full w-72 bg-n-alpha-3 backdrop-blur-[100px] border-n-weak"
      >
        <!-- Produto -->
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('KANBAN.TOOLBAR.PRODUCT') }}
          <select
            :value="filters.product"
            :class="fieldClass"
            @change="setFilter('product', $event.target.value)"
          >
            <option value="">{{ t('KANBAN.TOOLBAR.ALL_PRODUCTS') }}</option>
            <option v-for="product in products" :key="product" :value="product">
              {{ product }}
            </option>
          </select>
        </label>

        <!-- Etapa -->
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('KANBAN.TOOLBAR.STAGE') }}
          <select
            :value="filters.stage"
            :class="fieldClass"
            @change="setFilter('stage', $event.target.value)"
          >
            <option value="">{{ t('KANBAN.TOOLBAR.ALL_STAGES') }}</option>
            <option
              v-for="stage in stages"
              :key="stage.slug"
              :value="stage.slug"
            >
              {{ stage.name }}
            </option>
          </select>
        </label>

        <!-- Responsável -->
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('KANBAN.TOOLBAR.ASSIGNEE') }}
          <select
            :value="filters.assigneeId"
            :class="fieldClass"
            @change="setFilter('assigneeId', $event.target.value)"
          >
            <option value="">{{ t('KANBAN.TOOLBAR.ALL_ASSIGNEES') }}</option>
            <option
              v-for="assignee in assignees"
              :key="assignee.id"
              :value="String(assignee.id)"
            >
              {{ assignee.name }}
            </option>
          </select>
        </label>

        <!-- Data de criação (intervalo) -->
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('KANBAN.TOOLBAR.CREATED_FROM') }}
          <input
            :value="filters.createdFrom"
            type="date"
            :class="fieldClass"
            @change="setFilter('createdFrom', $event.target.value)"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('KANBAN.TOOLBAR.CREATED_TO_LABEL') }}
          <input
            :value="filters.createdTo"
            type="date"
            :class="fieldClass"
            @change="setFilter('createdTo', $event.target.value)"
          />
        </label>

        <!-- Ordenação -->
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('KANBAN.TOOLBAR.SORT_LABEL') }}
          <select
            :value="sortBy"
            :class="fieldClass"
            @change="emit('update:sort-by', $event.target.value)"
          >
            <option value="last_activity_desc">
              {{ t('KANBAN.TOOLBAR.SORT.LAST_ACTIVITY') }}
            </option>
            <option value="created_desc">
              {{ t('KANBAN.TOOLBAR.SORT.CREATED_DESC') }}
            </option>
            <option value="created_asc">
              {{ t('KANBAN.TOOLBAR.SORT.CREATED_ASC') }}
            </option>
            <option value="volume_desc">
              {{ t('KANBAN.TOOLBAR.SORT.VOLUME_DESC') }}
            </option>
          </select>
        </label>
      </div>
    </div>

    <!-- Limpar filtros -->
    <button
      v-if="hasActiveFilters"
      class="flex items-center h-8 gap-1 px-2.5 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2 ltr:ml-auto rtl:mr-auto"
      @click="emit('clear')"
    >
      <Icon icon="i-lucide-x" class="size-4" />
      {{ t('KANBAN.TOOLBAR.CLEAR') }}
    </button>
  </div>
</template>
