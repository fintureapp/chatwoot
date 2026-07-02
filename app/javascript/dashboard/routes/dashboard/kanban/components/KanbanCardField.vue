<script setup>
import { computed } from 'vue';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';

const props = defineProps({
  field: {
    type: Object,
    required: true,
  },
  value: {
    type: [String, Number, Array, Object, Boolean],
    default: null,
  },
});

const isEmpty = computed(() => {
  const { value } = props;
  if (Array.isArray(value)) return value.length === 0;
  return value === null || value === undefined || value === '';
});

const chips = computed(() =>
  Array.isArray(props.value) ? props.value : [props.value]
);

const formattedDate = computed(() => {
  const seconds = Number(props.value);
  if (!seconds) return '';
  return shortTimestamp(dynamicTime(seconds));
});

const formattedValue = computed(() => {
  const number = Number(props.value);
  if (Number.isFinite(number) && props.value !== '') {
    return number.toLocaleString('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    });
  }
  return props.value;
});
</script>

<template>
  <div v-if="!isEmpty" class="min-w-0">
    <span
      v-if="field.type === 'text' && field.primary"
      class="text-sm font-medium truncate text-n-slate-12"
    >
      {{ value }}
    </span>
    <span
      v-else-if="field.type === 'text'"
      class="block text-xs truncate text-n-slate-11"
    >
      {{ value }}
    </span>
    <span
      v-else-if="field.type === 'value'"
      :class="
        field.primary
          ? 'text-sm font-semibold text-n-teal-11'
          : 'text-xs text-n-slate-11'
      "
    >
      {{ formattedValue }}
    </span>
    <span
      v-else-if="field.type === 'date'"
      class="block text-xs text-n-slate-10"
    >
      {{ formattedDate }}
    </span>
    <div v-else-if="field.type === 'tag'" class="flex flex-wrap gap-1">
      <span
        v-for="chip in chips"
        :key="chip"
        class="px-1.5 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
      >
        {{ chip }}
      </span>
    </div>
  </div>
</template>
