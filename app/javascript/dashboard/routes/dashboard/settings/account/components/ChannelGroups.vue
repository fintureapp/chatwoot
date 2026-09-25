<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import {
  CHANNEL_GROUPS,
  resolveInboxChannelGroup,
} from 'dashboard/helper/channelGroupHelper';

const { t } = useI18n();
const { currentAccount, updateAccount } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');

const AUTO = 'auto';
// inbox id -> 'auto' | 'whatsapp' | 'email'
const selections = ref({});
const isSubmitting = ref(false);

const groupOptions = computed(() => [
  {
    value: AUTO,
    label: t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.OPTIONS.AUTO'),
  },
  {
    value: CHANNEL_GROUPS.WHATSAPP,
    label: t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.OPTIONS.WHATSAPP'),
  },
  {
    value: CHANNEL_GROUPS.EMAIL,
    label: t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.OPTIONS.EMAIL'),
  },
]);

const syncFromAccount = () => {
  const map = currentAccount.value?.custom_attributes?.channel_groups || {};
  const next = {};
  (inboxes.value || []).forEach(inbox => {
    const stored = map[inbox.id] ?? map[String(inbox.id)];
    next[inbox.id] =
      stored === CHANNEL_GROUPS.WHATSAPP || stored === CHANNEL_GROUPS.EMAIL
        ? stored
        : AUTO;
  });
  selections.value = next;
};

watch([currentAccount, inboxes], syncFromAccount, {
  immediate: true,
  deep: true,
});

const inboxRows = computed(() =>
  (inboxes.value || []).map(inbox => {
    const resolved = resolveInboxChannelGroup(inbox, {});
    return {
      id: inbox.id,
      name: inbox.name,
      icon: getInboxIconByType(inbox.channel_type, inbox.medium, 'line'),
      autoLabel: resolved
        ? t(
            `GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.OPTIONS.${resolved.toUpperCase()}`
          )
        : t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.AUTO_NONE'),
    };
  })
);

const handleSubmit = async () => {
  const map = {};
  Object.entries(selections.value).forEach(([inboxId, group]) => {
    if (group === CHANNEL_GROUPS.WHATSAPP || group === CHANNEL_GROUPS.EMAIL) {
      map[inboxId] = group;
    }
  });

  try {
    isSubmitting.value = true;
    await updateAccount({ channel_groups: map });
    useAlert(t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.API.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.NOTE')"
    with-border
  >
    <form class="grid gap-4" @submit.prevent="handleSubmit">
      <div
        v-if="inboxRows.length"
        class="rounded-xl border border-n-weak bg-n-solid-1 w-full text-sm text-n-slate-12 divide-y divide-n-weak"
      >
        <div
          v-for="inbox in inboxRows"
          :key="inbox.id"
          class="p-3 flex items-center justify-between gap-3"
        >
          <div class="flex items-center gap-2 min-w-0">
            <span :class="inbox.icon" class="size-4 shrink-0 text-n-slate-11" />
            <span class="truncate">{{ inbox.name }}</span>
          </div>
          <select
            v-model="selections[inbox.id]"
            class="!mb-0 text-sm w-40 shrink-0"
            :aria-label="
              t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.SELECT_ARIA', {
                inbox: inbox.name,
              })
            "
          >
            <option
              v-for="option in groupOptions"
              :key="option.value"
              :value="option.value"
            >
              {{
                option.value === AUTO
                  ? t(
                      'GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.OPTIONS.AUTO_WITH_HINT',
                      {
                        hint: inbox.autoLabel,
                      }
                    )
                  : option.label
              }}
            </option>
          </select>
        </div>
      </div>
      <p v-else class="text-n-slate-11 text-body-main">
        {{ t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.EMPTY') }}
      </p>
      <div v-if="inboxRows.length">
        <NextButton
          blue
          type="submit"
          :is-loading="isSubmitting"
          :label="t('GENERAL_SETTINGS.FORM.CHANNEL_GROUPS.UPDATE_BUTTON')"
        />
      </div>
    </form>
  </SectionLayout>
</template>
