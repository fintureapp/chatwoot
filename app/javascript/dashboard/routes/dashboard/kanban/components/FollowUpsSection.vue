<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    default: null,
  },
});

const store = useStore();
const { t } = useI18n();

const getFollowUps = useMapGetter('kanban/getFollowUps');
const uiFlags = useMapGetter('kanban/getFollowUpsUIFlags');

const followUps = computed(() =>
  props.conversationId ? getFollowUps.value(props.conversationId) : []
);

const creating = ref(false);
const titleDraft = ref('');
const dueAtDraft = ref('');

const pending = computed(() =>
  followUps.value.filter(item => !item.completed_at)
);
const completed = computed(() =>
  followUps.value.filter(item => item.completed_at)
);

const isOverdue = item =>
  !item.completed_at && new Date(item.due_at).getTime() < Date.now();

const formatDueAt = value =>
  new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));

const resetForm = () => {
  creating.value = false;
  titleDraft.value = '';
  dueAtDraft.value = '';
};

const create = async () => {
  if (!titleDraft.value.trim() || !dueAtDraft.value) return;
  try {
    await store.dispatch('kanban/createFollowUp', {
      conversationId: props.conversationId,
      followUp: {
        title: titleDraft.value.trim(),
        due_at: new Date(dueAtDraft.value).toISOString(),
      },
    });
    resetForm();
  } catch {
    useAlert(t('KANBAN.FOLLOW_UPS.SAVE_ERROR'));
  }
};

const toggleComplete = async item => {
  try {
    await store.dispatch('kanban/updateFollowUp', {
      conversationId: props.conversationId,
      followUpId: item.id,
      changes: { completed: !item.completed_at },
    });
  } catch {
    useAlert(t('KANBAN.FOLLOW_UPS.SAVE_ERROR'));
  }
};

const remove = async item => {
  try {
    await store.dispatch('kanban/deleteFollowUp', {
      conversationId: props.conversationId,
      followUpId: item.id,
    });
  } catch {
    useAlert(t('KANBAN.FOLLOW_UPS.SAVE_ERROR'));
  }
};

watch(
  () => props.conversationId,
  conversationId => {
    resetForm();
    if (conversationId) {
      store.dispatch('kanban/fetchFollowUps', { conversationId });
    }
  },
  { immediate: true }
);
</script>

<template>
  <section class="flex flex-col gap-2">
    <div class="flex items-center justify-between">
      <h3 class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        {{ $t('KANBAN.FOLLOW_UPS.TITLE') }}
        <span v-if="pending.length" class="ml-1 text-n-slate-11">
          ({{ pending.length }})
        </span>
      </h3>
      <button
        v-if="!creating"
        class="text-xs text-n-brand hover:underline"
        @click="creating = true"
      >
        {{ $t('KANBAN.DRAWER.ADD') }}
      </button>
    </div>

    <!-- Novo follow-up -->
    <div v-if="creating" class="flex flex-col gap-2">
      <input
        v-model="titleDraft"
        type="text"
        :maxlength="200"
        :placeholder="$t('KANBAN.FOLLOW_UPS.TITLE_PLACEHOLDER')"
        class="h-8 px-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
      />
      <input
        v-model="dueAtDraft"
        type="datetime-local"
        class="h-8 px-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
      />
      <div class="flex items-center gap-2">
        <button
          class="px-3 h-8 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
          :disabled="!titleDraft.trim() || !dueAtDraft || uiFlags.isSaving"
          @click="create"
        >
          {{ $t('KANBAN.DRAWER.SAVE') }}
        </button>
        <button
          class="px-3 h-8 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click="resetForm"
        >
          {{ $t('KANBAN.DRAWER.CANCEL') }}
        </button>
      </div>
    </div>

    <div
      v-if="uiFlags.isFetching && !followUps.length"
      class="flex items-center justify-center py-4 text-n-slate-11"
    >
      <Spinner />
    </div>

    <p
      v-else-if="!followUps.length && !creating"
      class="text-sm italic text-n-slate-10"
    >
      {{ $t('KANBAN.FOLLOW_UPS.EMPTY') }}
    </p>

    <ul v-else class="flex flex-col gap-2">
      <li
        v-for="item in [...pending, ...completed]"
        :key="item.id"
        class="flex items-start gap-2 p-2 text-sm rounded-lg group bg-n-alpha-1"
      >
        <button
          class="mt-0.5 shrink-0"
          :title="
            item.completed_at
              ? $t('KANBAN.FOLLOW_UPS.REOPEN')
              : $t('KANBAN.FOLLOW_UPS.COMPLETE')
          "
          @click="toggleComplete(item)"
        >
          <Icon
            :icon="
              item.completed_at ? 'i-lucide-check-circle-2' : 'i-lucide-circle'
            "
            class="size-4"
            :class="item.completed_at ? 'text-n-teal-11' : 'text-n-slate-10'"
          />
        </button>
        <div class="flex flex-col min-w-0 flex-1">
          <span
            class="break-words"
            :class="
              item.completed_at
                ? 'line-through text-n-slate-10'
                : 'text-n-slate-12'
            "
          >
            {{ item.title }}
          </span>
          <span
            class="text-xs"
            :class="
              isOverdue(item) ? 'text-n-ruby-11 font-medium' : 'text-n-slate-10'
            "
          >
            <Icon
              v-if="isOverdue(item)"
              icon="i-lucide-bell-ring"
              class="inline size-3"
            />
            {{ formatDueAt(item.due_at) }}
            <template v-if="item.user_name"> · {{ item.user_name }}</template>
          </span>
        </div>
        <button
          class="hidden shrink-0 text-n-slate-10 hover:text-n-ruby-11 group-hover:block"
          :title="$t('KANBAN.FOLLOW_UPS.DELETE')"
          @click="remove(item)"
        >
          <Icon icon="i-lucide-trash-2" class="size-4" />
        </button>
      </li>
    </ul>
  </section>
</template>
