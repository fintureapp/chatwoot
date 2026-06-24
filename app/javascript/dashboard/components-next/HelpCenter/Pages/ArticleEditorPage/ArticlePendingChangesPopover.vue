<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['apply', 'discard']);

const { t } = useI18n();

const isOpen = ref(false);
// Which button is in flight, so only that one shows the spinner.
const activeAction = ref(null);

const open = () => {
  activeAction.value = null;
  isOpen.value = true;
};

const close = () => {
  isOpen.value = false;
};

// Don't let a click-outside or Escape dismiss the popover mid-action.
const dismiss = () => {
  if (!props.isLoading) close();
};

const onApply = () => {
  activeAction.value = 'apply';
  emit('apply');
};

const onDiscard = () => {
  activeAction.value = 'discard';
  emit('discard');
};

onKeyStroke('Escape', () => {
  if (isOpen.value) dismiss();
});

defineExpose({ open, close });
</script>

<template>
  <div
    v-show="isOpen"
    v-on-click-outside="dismiss"
    class="absolute z-50 flex flex-col gap-4 p-4 mt-2 outline outline-1 shadow-lg w-96 end-0 top-full rounded-xl bg-n-alpha-3 backdrop-blur-[100px] outline-n-container"
  >
    <div class="flex flex-col gap-1">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('HELP_CENTER.EDIT_ARTICLE_PAGE.PENDING_CHANGES_POPOVER.TITLE') }}
      </h3>
      <p class="mb-0 text-sm text-n-slate-11">
        {{
          t('HELP_CENTER.EDIT_ARTICLE_PAGE.PENDING_CHANGES_POPOVER.DESCRIPTION')
        }}
      </p>
    </div>
    <div class="flex items-center justify-between gap-2">
      <Button
        type="button"
        variant="faded"
        color="ruby"
        size="sm"
        class="flex-1"
        :is-loading="isLoading && activeAction === 'discard'"
        :disabled="isLoading"
        :label="
          t('HELP_CENTER.EDIT_ARTICLE_PAGE.PENDING_CHANGES_POPOVER.DISCARD')
        "
        @click="onDiscard"
      />
      <Button
        type="button"
        color="blue"
        size="sm"
        class="flex-1"
        :is-loading="isLoading && activeAction === 'apply'"
        :disabled="isLoading"
        :label="
          t('HELP_CENTER.EDIT_ARTICLE_PAGE.PENDING_CHANGES_POPOVER.APPLY')
        "
        @click="onApply"
      />
    </div>
  </div>
</template>
