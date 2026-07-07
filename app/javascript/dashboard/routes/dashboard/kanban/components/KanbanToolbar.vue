<script setup>
import { useI18n } from 'vue-i18n';
import { KANBAN_STAGES } from 'dashboard/routes/dashboard/kanban/config/stages';
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
});

const emit = defineEmits(['update:filters', 'update:sortBy', 'clear']);

const { t } = useI18n();

const setFilter = (key, value) => {
  emit('update:filters', { ...props.filters, [key]: value });
};

const inputClass =
  'h-9 px-3 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand';
</script>

<template>
  <div class="flex flex-wrap items-center gap-2 px-6 py-3 border-b border-n-weak">
    <!-- Busca textual (cliente / produto) -->
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
        class="w-56 ltr:pl-8 rtl:pr-8"
        @input="setFilter('query', $event.target.value)"
      />
    </div>

    <!-- Produto -->
    <select
      :value="filters.product"
      :class="inputClass"
      @change="setFilter('product', $event.target.value)"
    >
      <option value="">{{ t('KANBAN.TOOLBAR.ALL_PRODUCTS') }}</option>
      <option v-for="product in products" :key="product" :value="product">
        {{ product }}
      </option>
    </select>

    <!-- Etapa -->
    <select
      :value="filters.stage"
      :class="inputClass"
      @change="setFilter('stage', $event.target.value)"
    >
      <option value="">{{ t('KANBAN.TOOLBAR.ALL_STAGES') }}</option>
      <option v-for="stage in KANBAN_STAGES" :key="stage.value" :value="stage.value">
        {{ stage.label }}
      </option>
    </select>

    <!-- Responsável -->
    <select
      :value="filters.assigneeId"
      :class="inputClass"
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

    <!-- Data de criação (intervalo) -->
    <label class="flex items-center gap-1 text-xs text-n-slate-11">
      {{ t('KANBAN.TOOLBAR.CREATED_FROM') }}
      <input
        :value="filters.createdFrom"
        type="date"
        :class="inputClass"
        @change="setFilter('createdFrom', $event.target.value)"
      />
    </label>
    <label class="flex items-center gap-1 text-xs text-n-slate-11">
      {{ t('KANBAN.TOOLBAR.CREATED_TO') }}
      <input
        :value="filters.createdTo"
        type="date"
        :class="inputClass"
        @change="setFilter('createdTo', $event.target.value)"
      />
    </label>

    <!-- Ordenação -->
    <select
      :value="sortBy"
      :class="inputClass"
      class="ltr:ml-auto rtl:mr-auto"
      @change="emit('update:sortBy', $event.target.value)"
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

    <button
      v-if="hasActiveFilters"
      class="flex items-center gap-1 px-2.5 h-9 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
      @click="emit('clear')"
    >
      <Icon icon="i-lucide-x" class="size-4" />
      {{ t('KANBAN.TOOLBAR.CLEAR') }}
    </button>
  </div>
</template>
