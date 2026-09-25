<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { CHANNEL_GROUPS } from 'dashboard/helper/channelGroupHelper';

const props = defineProps({
  // null = "All". Otherwise a value from CHANNEL_GROUPS.
  modelValue: {
    type: String,
    default: null,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const options = computed(() => [
  {
    key: 'all',
    value: null,
    icon: 'i-lucide-inbox',
    label: t('CHAT_LIST.CHANNEL_FILTER.ALL'),
  },
  {
    key: 'whatsapp',
    value: CHANNEL_GROUPS.WHATSAPP,
    icon: 'i-ri-whatsapp-fill',
    label: t('CHAT_LIST.CHANNEL_FILTER.WHATSAPP'),
  },
  {
    key: 'email',
    value: CHANNEL_GROUPS.EMAIL,
    icon: 'i-ri-mail-fill',
    label: t('CHAT_LIST.CHANNEL_FILTER.EMAIL'),
  },
]);

const isActive = value => props.modelValue === value;

const selectOption = value => {
  if (isActive(value)) return;
  emit('update:modelValue', value);
};
</script>

<template>
  <div
    class="flex items-center gap-0.5 p-0.5 rounded-lg bg-n-alpha-1"
    role="group"
    :aria-label="$t('CHAT_LIST.CHANNEL_FILTER.ARIA_LABEL')"
  >
    <NextButton
      v-for="option in options"
      :key="option.key"
      v-tooltip.top="option.label"
      :icon="option.icon"
      ghost
      slate
      xs
      :aria-label="option.label"
      :aria-pressed="isActive(option.value)"
      class="!rounded-md transition-colors duration-150"
      :class="{
        'bg-n-solid-1 !text-n-slate-12 shadow-sm': isActive(option.value),
        '!text-n-slate-11': !isActive(option.value),
      }"
      @click="selectOption(option.value)"
    />
  </div>
</template>
