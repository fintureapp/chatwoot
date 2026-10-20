<script setup>
import { computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { CHANNEL_GROUPS } from 'dashboard/helper/channelGroupHelper';
import {
  OTHER_CHANNEL_TYPE,
  countQuickFilters,
  emptyQuickFilters,
  inboxesForTipos,
  stageOptionsFor,
} from 'dashboard/helper/quickFilterHelper';
import QuickFilterDropdown from './QuickFilterDropdown.vue';

// Barra "Filtros" da lista de conversas, em pílulas que quebram linha:
// Tipo → Caixa → Coluna do Kanban (cada um restringe o seguinte), depois
// Status, Prioridade, Etiqueta, Time e Agente. Cada mudança emite `change`.
const props = defineProps({
  modelValue: { type: Object, required: true },
  inboxes: { type: Array, default: () => [] },
  channelGroupsMap: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue', 'change']);

const { t } = useI18n();
const store = useStore();
const labels = useMapGetter('labels/getLabels');
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');
const stagesByInbox = computed(() => store.state.kanban?.stagesByInbox || {});

onMounted(() => {
  if (!agents.value?.length) store.dispatch('agents/get');
  if (!teams.value?.length) store.dispatch('teams/get');
});

const tipoOptions = computed(() => [
  {
    id: CHANNEL_GROUPS.WHATSAPP,
    name: t('CHAT_LIST.QUICK_FILTERS.TYPE_WHATSAPP'),
    icon: 'i-ri-whatsapp-fill',
  },
  {
    id: CHANNEL_GROUPS.EMAIL,
    name: t('CHAT_LIST.QUICK_FILTERS.TYPE_EMAIL'),
    icon: 'i-ri-mail-fill',
  },
  {
    id: OTHER_CHANNEL_TYPE,
    name: t('CHAT_LIST.QUICK_FILTERS.TYPE_OTHER'),
    icon: 'i-lucide-mailbox',
  },
]);
const typedInboxes = tipos =>
  inboxesForTipos(tipos, props.inboxes, props.channelGroupsMap);
const inboxOptions = computed(() =>
  typedInboxes(props.modelValue.tipo).map(inbox => ({
    id: inbox.id,
    name: inbox.name,
  }))
);
const stageOptions = computed(() =>
  stageOptionsFor(props.modelValue.inbox, stagesByInbox.value).map(stage => ({
    id: stage.slug,
    name: stage.name,
  }))
);
const statusOptions = computed(() => [
  { id: 'open', name: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.open.TEXT') },
  { id: 'pending', name: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.pending.TEXT') },
  { id: 'snoozed', name: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.snoozed.TEXT') },
  {
    id: 'resolved',
    name: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.resolved.TEXT'),
  },
]);
const priorityOptions = computed(() => [
  { id: 'urgent', name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
  { id: 'high', name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
  { id: 'medium', name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
  { id: 'low', name: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
]);
const labelOptions = computed(() =>
  (labels.value || []).map(label => ({
    id: label.title,
    name: label.title,
    color: label.color,
  }))
);
const teamOptions = computed(() =>
  (teams.value || []).map(team => ({ id: team.id, name: team.name }))
);
const agentOptions = computed(() =>
  (agents.value || []).map(agent => ({
    id: agent.id,
    name: agent.available_name || agent.name,
  }))
);

const hasFilters = computed(() => countQuickFilters(props.modelValue) > 0);

const emitFilters = next => {
  emit('update:modelValue', next);
  emit('change', next);
};

const update = (key, values) => {
  const next = { ...props.modelValue, [key]: values };
  // Tipo → Caixa → Coluna: ao mudar um, descarta o que deixou de valer abaixo.
  if (key === 'tipo') {
    const validInboxes = typedInboxes(values).map(inbox => inbox.id);
    next.inbox = next.inbox.filter(id => validInboxes.includes(id));
  }
  if (key === 'tipo' || key === 'inbox') {
    const validStages = stageOptionsFor(next.inbox, stagesByInbox.value).map(
      stage => stage.slug
    );
    next.stage = next.inbox.length
      ? next.stage.filter(slug => validStages.includes(slug))
      : [];
  }
  emitFilters(next);
};

const clearAll = () => emitFilters(emptyQuickFilters());

// Carrega as colunas das caixas escolhidas (cacheadas no módulo kanban).
watch(
  () => props.modelValue.inbox,
  inboxIds => {
    inboxIds
      .filter(id => !stagesByInbox.value[id])
      .forEach(inboxId =>
        store.dispatch('kanban/fetchStages', { inboxId }).catch(() => {})
      );
  },
  { immediate: true }
);

const filters = computed(() => [
  {
    key: 'tipo',
    label: t('CHAT_LIST.QUICK_FILTERS.TYPE'),
    icon: 'i-lucide-radio-tower',
    options: tipoOptions.value,
  },
  {
    key: 'inbox',
    label: t('CHAT_LIST.QUICK_FILTERS.INBOX'),
    icon: 'i-lucide-inbox',
    options: inboxOptions.value,
  },
  {
    key: 'stage',
    label: t('CHAT_LIST.QUICK_FILTERS.STAGE'),
    icon: 'i-lucide-square-kanban',
    options: stageOptions.value,
    disabled: !props.modelValue.inbox.length,
    disabledHint: t('CHAT_LIST.QUICK_FILTERS.STAGE_NEEDS_INBOX'),
  },
  {
    key: 'status',
    label: t('CHAT_LIST.QUICK_FILTERS.STATUS'),
    icon: 'i-lucide-circle-dot',
    options: statusOptions.value,
  },
  {
    key: 'priority',
    label: t('CHAT_LIST.QUICK_FILTERS.PRIORITY'),
    icon: 'i-lucide-signal',
    options: priorityOptions.value,
  },
  {
    key: 'label',
    label: t('CHAT_LIST.QUICK_FILTERS.LABEL'),
    icon: 'i-lucide-tag',
    options: labelOptions.value,
  },
  {
    key: 'team',
    label: t('CHAT_LIST.QUICK_FILTERS.TEAM'),
    icon: 'i-lucide-users',
    options: teamOptions.value,
  },
  {
    key: 'agent',
    label: t('CHAT_LIST.QUICK_FILTERS.AGENT'),
    icon: 'i-lucide-user-round',
    options: agentOptions.value,
  },
]);
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-1.5 px-3 py-2.5 border-b border-n-weak"
  >
    <QuickFilterDropdown
      v-for="filter in filters"
      :key="filter.key"
      :model-value="modelValue[filter.key]"
      :label="filter.label"
      :icon="filter.icon"
      :options="filter.options"
      :disabled="filter.disabled"
      :disabled-hint="filter.disabledHint"
      :empty-hint="t('CHAT_LIST.QUICK_FILTERS.NO_OPTIONS')"
      :search-placeholder="t('CHAT_LIST.QUICK_FILTERS.SEARCH')"
      @update:model-value="values => update(filter.key, values)"
    />
    <button
      v-if="hasFilters"
      type="button"
      class="h-7 px-1.5 text-xs text-n-slate-11 hover:text-n-slate-12 hover:underline"
      @click="clearAll"
    >
      {{ t('CHAT_LIST.QUICK_FILTERS.CLEAR') }}
    </button>
  </div>
</template>
