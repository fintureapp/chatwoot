<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  resolveStage,
  stageLabel,
  lostReasonLabel,
  LOST_STAGE,
  NEXT_ACTION_ATTRIBUTE_KEY,
  LOST_REASON_ATTRIBUTE_KEY,
  LOST_COMMENT_ATTRIBUTE_KEY,
  HISTORY_ATTRIBUTE_KEY,
} from 'dashboard/routes/dashboard/kanban/config/stages';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  open: {
    type: Boolean,
    default: false,
  },
  conversationId: {
    type: [Number, String],
    default: null,
  },
  intent: {
    type: String,
    default: 'detail',
  },
  inboxNames: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['update:open']);

const store = useStore();
const { t } = useI18n();

const getRecordById = useMapGetter('kanban/getRecordById');
const getNotes = useMapGetter('kanban/getNotes');
const notesUiFlags = useMapGetter('kanban/getNotesUIFlags');

const record = computed(() =>
  props.conversationId ? getRecordById.value(props.conversationId) : null
);
const notes = computed(() =>
  props.conversationId ? getNotes.value(props.conversationId) : []
);

const nextActionEditing = ref(false);
const nextActionDraft = ref('');
const isSavingNextAction = ref(false);
const noteDraft = ref('');
const noteInputRef = ref(null);
const nextActionInputRef = ref(null);

// ---- Formatação -----------------------------------------------------------
const formatDateTime = seconds => {
  if (!seconds) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(seconds * 1000));
};

const NOT_INFORMED = () => t('KANBAN.DRAWER.NOT_INFORMED');

const custom = key => record.value?.custom_attributes?.[key];

const currentStage = computed(() =>
  record.value ? stageLabel(resolveStage(record.value)) : ''
);
const isLost = computed(() => resolveStage(record.value) === LOST_STAGE);

const volume = computed(() => {
  const raw = custom('valor_potencial');
  const number = Number(raw);
  if (raw === undefined || raw === null || raw === '' || !Number.isFinite(number)) {
    return '';
  }
  return number.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
});

const nextAction = computed(() => custom(NEXT_ACTION_ATTRIBUTE_KEY) || '');

const detailRows = computed(() => {
  const sender = record.value?.meta?.sender || {};
  return [
    { key: 'client', label: t('KANBAN.DRAWER.FIELDS.CLIENT'), value: sender.name },
    { key: 'phone', label: t('KANBAN.DRAWER.FIELDS.PHONE'), value: sender.phone_number },
    { key: 'email', label: t('KANBAN.DRAWER.FIELDS.EMAIL'), value: sender.email },
    { key: 'product', label: t('KANBAN.DRAWER.FIELDS.PRODUCT'), value: custom('produto_interesse') },
    { key: 'volume', label: t('KANBAN.DRAWER.FIELDS.VOLUME'), value: volume.value },
    { key: 'stage', label: t('KANBAN.DRAWER.FIELDS.STAGE'), value: currentStage.value },
    { key: 'assignee', label: t('KANBAN.DRAWER.FIELDS.ASSIGNEE'), value: record.value?.meta?.assignee?.name },
    { key: 'inbox', label: t('KANBAN.DRAWER.FIELDS.INBOX'), value: props.inboxNames[record.value?.inbox_id] },
    { key: 'createdAt', label: t('KANBAN.DRAWER.FIELDS.CREATED_AT'), value: formatDateTime(record.value?.created_at) },
    { key: 'updatedAt', label: t('KANBAN.DRAWER.FIELDS.UPDATED_AT'), value: formatDateTime(record.value?.last_activity_at) },
  ];
});

const lostReason = computed(() =>
  isLost.value ? lostReasonLabel(custom(LOST_REASON_ATTRIBUTE_KEY)) : ''
);
const lostComment = computed(() =>
  isLost.value ? custom(LOST_COMMENT_ATTRIBUTE_KEY) || '' : ''
);

// ---- Histórico ------------------------------------------------------------
const history = computed(() => {
  const rec = record.value;
  if (!rec) return [];
  const entries = Array.isArray(rec.custom_attributes?.[HISTORY_ATTRIBUTE_KEY])
    ? [...rec.custom_attributes[HISTORY_ATTRIBUTE_KEY]]
    : [];
  const rendered = entries.map(entry => ({
    id: entry.id,
    at: entry.at,
    title: t('KANBAN.DRAWER.HISTORY.STAGE_CHANGE', {
      from: stageLabel(entry.from),
      to: stageLabel(entry.to),
    }),
    detail: entry.reason ? lostReasonLabel(entry.reason) : '',
    author: entry.by?.name || '',
  }));
  // Entrada sintética de criação (não é armazenada; derivada de created_at).
  rendered.unshift({
    id: 'created',
    at: rec.created_at,
    title: t('KANBAN.DRAWER.HISTORY.CREATED'),
    detail: '',
    author: '',
  });
  // Mais recente primeiro.
  return rendered.sort((a, b) => (b.at || 0) - (a.at || 0));
});

// ---- Ações ----------------------------------------------------------------
const close = () => emit('update:open', false);

const startEditNextAction = async () => {
  nextActionDraft.value = nextAction.value;
  nextActionEditing.value = true;
  await nextTick();
  nextActionInputRef.value?.focus();
};

const saveNextAction = async () => {
  if (!record.value) return;
  isSavingNextAction.value = true;
  try {
    await store.dispatch('kanban/updateNextAction', {
      conversationId: props.conversationId,
      nextAction: nextActionDraft.value.trim(),
    });
    nextActionEditing.value = false;
  } catch {
    useAlert(t('KANBAN.ERRORS.UPDATE_NEXT_ACTION'));
  } finally {
    isSavingNextAction.value = false;
  }
};

const submitNote = async () => {
  const content = noteDraft.value.trim();
  if (!content) return;
  try {
    await store.dispatch('kanban/addNote', {
      conversationId: props.conversationId,
      content,
    });
    noteDraft.value = '';
  } catch {
    useAlert(t('KANBAN.ERRORS.ADD_NOTE'));
  }
};

onKeyStroke('Escape', () => {
  if (props.open) close();
});

// Ao abrir: busca notas e aplica o "intent" (foco em nota / edição de próxima ação).
watch(
  () => [props.open, props.conversationId],
  ([open]) => {
    if (!open || !props.conversationId) return;
    store.dispatch('kanban/fetchNotes', { conversationId: props.conversationId });
    nextActionEditing.value = false;
    noteDraft.value = '';
    nextTick(() => {
      if (props.intent === 'note') noteInputRef.value?.focus();
      if (props.intent === 'next-action') startEditNextAction();
    });
  },
  { immediate: true }
);
</script>

<template>
  <Teleport to="body">
    <Transition name="kanban-drawer-fade">
      <div
        v-if="open"
        class="fixed inset-0 z-50 bg-n-alpha-black1 backdrop-blur-[2px]"
        @click="close"
      />
    </Transition>
    <Transition name="kanban-drawer-slide">
      <aside
        v-if="open"
        class="fixed inset-y-0 z-50 flex flex-col w-full max-w-md shadow-xl ltr:right-0 rtl:left-0 bg-n-solid-1 border-n-weak ltr:border-l rtl:border-r"
      >
        <!-- Header -->
        <header
          class="flex items-center gap-3 px-5 py-4 border-b shrink-0 border-n-weak"
        >
          <Avatar
            :name="record?.meta?.sender?.name"
            :src="record?.meta?.sender?.thumbnail"
            :size="32"
            rounded-full
          />
          <div class="flex flex-col min-w-0">
            <h2 class="text-base font-medium truncate text-n-slate-12">
              {{ record?.meta?.sender?.name || NOT_INFORMED() }}
            </h2>
            <span class="text-xs text-n-slate-11">{{ currentStage }}</span>
          </div>
          <button
            class="flex items-center justify-center ml-auto rounded-md size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :title="$t('KANBAN.DRAWER.CLOSE')"
            @click="close"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </header>

        <div class="flex flex-col flex-1 gap-6 px-5 py-4 overflow-y-auto">
          <!-- Detalhes -->
          <section class="flex flex-col gap-2">
            <h3
              class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              {{ $t('KANBAN.DRAWER.SECTIONS.DETAILS') }}
            </h3>
            <dl class="flex flex-col gap-2">
              <div
                v-for="row in detailRows"
                :key="row.key"
                class="flex items-start gap-3 text-sm"
              >
                <dt class="w-32 shrink-0 text-n-slate-11">{{ row.label }}</dt>
                <dd
                  class="min-w-0 break-words"
                  :class="row.value ? 'text-n-slate-12' : 'text-n-slate-10 italic'"
                >
                  {{ row.value || NOT_INFORMED() }}
                </dd>
              </div>
              <div
                v-if="isLost && lostReason"
                class="flex items-start gap-3 text-sm"
              >
                <dt class="w-32 shrink-0 text-n-slate-11">
                  {{ $t('KANBAN.DRAWER.FIELDS.LOST_REASON') }}
                </dt>
                <dd class="min-w-0 break-words text-n-ruby-11">
                  {{ lostReason }}<template v-if="lostComment"> — {{ lostComment }}</template>
                </dd>
              </div>
            </dl>
          </section>

          <!-- Próxima ação -->
          <section class="flex flex-col gap-2">
            <div class="flex items-center justify-between">
              <h3
                class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
              >
                {{ $t('KANBAN.DRAWER.SECTIONS.NEXT_ACTION') }}
              </h3>
              <button
                v-if="!nextActionEditing"
                class="text-xs text-n-brand hover:underline"
                @click="startEditNextAction"
              >
                {{ nextAction ? $t('KANBAN.DRAWER.EDIT') : $t('KANBAN.DRAWER.ADD') }}
              </button>
            </div>
            <template v-if="nextActionEditing">
              <textarea
                ref="nextActionInputRef"
                v-model="nextActionDraft"
                rows="2"
                :maxlength="1000"
                :placeholder="$t('KANBAN.DRAWER.NEXT_ACTION_PLACEHOLDER')"
                class="w-full px-3 py-2 text-sm border rounded-lg resize-none bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
              />
              <div class="flex items-center gap-2">
                <button
                  class="px-3 h-8 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
                  :disabled="isSavingNextAction"
                  @click="saveNextAction"
                >
                  {{ $t('KANBAN.DRAWER.SAVE') }}
                </button>
                <button
                  class="px-3 h-8 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
                  @click="nextActionEditing = false"
                >
                  {{ $t('KANBAN.DRAWER.CANCEL') }}
                </button>
              </div>
            </template>
            <p
              v-else
              class="text-sm"
              :class="nextAction ? 'text-n-slate-12' : 'text-n-slate-10 italic'"
            >
              {{ nextAction || $t('KANBAN.DRAWER.NO_NEXT_ACTION') }}
            </p>
          </section>

          <!-- Notas -->
          <section class="flex flex-col gap-2">
            <h3
              class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              {{ $t('KANBAN.DRAWER.SECTIONS.NOTES') }}
            </h3>
            <div class="flex flex-col gap-2">
              <textarea
                ref="noteInputRef"
                v-model="noteDraft"
                rows="2"
                :maxlength="1000"
                :placeholder="$t('KANBAN.DRAWER.NOTE_PLACEHOLDER')"
                class="w-full px-3 py-2 text-sm border rounded-lg resize-none bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
              />
              <button
                class="self-start px-3 h-8 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
                :disabled="!noteDraft.trim() || notesUiFlags.isCreating"
                @click="submitNote"
              >
                {{ $t('KANBAN.DRAWER.ADD_NOTE') }}
              </button>
            </div>

            <div
              v-if="notesUiFlags.isFetching"
              class="flex items-center justify-center py-4 text-n-slate-11"
            >
              <Spinner />
            </div>
            <p
              v-else-if="notesUiFlags.hasError"
              class="py-2 text-sm text-n-ruby-11"
            >
              {{ $t('KANBAN.DRAWER.NOTES_ERROR') }}
            </p>
            <p
              v-else-if="!notes.length"
              class="py-2 text-sm text-n-slate-10 italic"
            >
              {{ $t('KANBAN.DRAWER.NO_NOTES') }}
            </p>
            <ul v-else class="flex flex-col gap-2">
              <li
                v-for="note in notes"
                :key="note.id"
                class="p-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12"
              >
                <p class="whitespace-pre-wrap break-words">{{ note.content }}</p>
                <p class="mt-1 text-xs text-n-slate-10">
                  <template v-if="note.author">{{ note.author }} · </template>
                  {{ formatDateTime(note.createdAt) }}
                </p>
              </li>
            </ul>
          </section>

          <!-- Histórico -->
          <section class="flex flex-col gap-2">
            <h3
              class="text-xs font-semibold tracking-wide uppercase text-n-slate-10"
            >
              {{ $t('KANBAN.DRAWER.SECTIONS.HISTORY') }}
            </h3>
            <ul class="flex flex-col gap-3">
              <li
                v-for="event in history"
                :key="event.id"
                class="flex gap-3 text-sm"
              >
                <span class="mt-1.5 size-2 rounded-full shrink-0 bg-n-slate-8" />
                <div class="flex flex-col min-w-0">
                  <span class="text-n-slate-12">{{ event.title }}</span>
                  <span v-if="event.detail" class="text-n-slate-11">
                    {{ event.detail }}
                  </span>
                  <span class="text-xs text-n-slate-10">
                    <template v-if="event.author">{{ event.author }} · </template>
                    {{ formatDateTime(event.at) }}
                  </span>
                </div>
              </li>
            </ul>
          </section>
        </div>
      </aside>
    </Transition>
  </Teleport>
</template>

<style scoped lang="scss">
.kanban-drawer-fade-enter-active,
.kanban-drawer-fade-leave-active {
  @apply transition-opacity duration-200;
}
.kanban-drawer-fade-enter-from,
.kanban-drawer-fade-leave-to {
  @apply opacity-0;
}
.kanban-drawer-slide-enter-active,
.kanban-drawer-slide-leave-active {
  @apply transition-transform duration-200 ease-out;
}
.kanban-drawer-slide-enter-from,
.kanban-drawer-slide-leave-to {
  @apply ltr:translate-x-full rtl:-translate-x-full;
}
</style>
