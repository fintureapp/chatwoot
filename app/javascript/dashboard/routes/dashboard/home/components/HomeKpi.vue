<script setup>
// Indicador da Home. `value` null = métrica sem fonte confiável: mostra
// "Indisponível" com o motivo, nunca 0, e não abre lista.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { deltaOf } from '../helpers';

const props = defineProps({
  label: { type: String, required: true },
  value: { type: Number, default: null },
  // 'number' | 'currency' (R$, sem centavos)
  format: { type: String, default: 'number' },
  icon: { type: String, default: '' },
  hint: { type: String, default: '' },
  unavailableReason: { type: String, default: '' },
  // 'crit' | 'warn' realçam o número quando ele é maior que zero.
  tone: { type: String, default: 'default' },
  // Valor do período anterior e com quem compara ("nos 7 dias anteriores").
  // Sobe/desce vem no ícone e no texto, não só na cor; o valor anterior vai
  // junto porque percentual sobre base pequena engana (2 -> 22 = +1000%).
  previous: { type: Number, default: null },
  compareLabel: { type: String, default: '' },
});

const emit = defineEmits(['open']);
const { t } = useI18n();

const isUnavailable = computed(() => props.value === null);
const formatters = {
  number: new Intl.NumberFormat('pt-BR'),
  currency: new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  }),
};
const fmt = number =>
  (formatters[props.format] || formatters.number).format(number);
const formatted = computed(() => fmt(props.value));
const highlight = computed(() => (props.value > 0 ? props.tone : 'default'));

const DELTA_ICONS = {
  up: 'i-lucide-trending-up',
  down: 'i-lucide-trending-down',
  flat: 'i-lucide-minus',
};
const delta = computed(() => deltaOf(props.value, props.previous));
const deltaText = computed(() => {
  const { direction, pct } = delta.value;
  const base = t('FINTURE_HOME.KPI.DELTA_BASE', {
    previous: fmt(props.previous),
    vs: props.compareLabel,
  });
  if (direction === 'flat' || pct === null) return base;
  const sign = pct > 0 ? '+' : '−';
  return `${sign}${Math.abs(pct)}% ${base}`;
});
</script>

<template>
  <button
    type="button"
    class="flex flex-col h-full gap-2 p-4 text-left rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak min-h-[120px] transition-colors group"
    :class="
      isUnavailable
        ? 'cursor-default'
        : 'hover:outline-n-slate-6 focus-visible:outline-n-brand'
    "
    :disabled="isUnavailable"
    :title="isUnavailable ? '' : t('FINTURE_HOME.KPI.OPEN_LIST')"
    @click="emit('open')"
  >
    <span class="flex items-start gap-1.5 min-h-8 text-n-slate-11">
      <Icon v-if="icon" :icon="icon" class="size-4 shrink-0" />
      <span class="text-xs">{{ label }}</span>
      <Icon
        v-if="!isUnavailable"
        icon="i-lucide-arrow-up-right"
        class="ml-auto transition-opacity opacity-0 size-3.5 group-hover:opacity-100"
      />
    </span>
    <template v-if="isUnavailable">
      <span class="text-base font-medium text-n-slate-10">
        {{ t('FINTURE_HOME.KPI.UNAVAILABLE') }}
      </span>
      <span v-if="unavailableReason" class="text-xs text-n-slate-10">
        {{ unavailableReason }}
      </span>
    </template>
    <template v-else>
      <span
        class="text-[32px] font-semibold leading-none tracking-tight tabular-nums"
        :class="{
          'text-n-slate-12': highlight === 'default',
          'text-n-ruby-11': highlight === 'crit',
          'text-n-amber-11': highlight === 'warn',
        }"
      >
        {{ formatted }}
      </span>
      <span v-if="hint" class="text-xs text-n-slate-10">{{ hint }}</span>
      <span
        v-if="delta"
        class="flex items-center gap-1 mt-auto text-xs text-n-slate-11"
      >
        <Icon :icon="DELTA_ICONS[delta.direction]" class="size-3.5 shrink-0" />
        {{ deltaText }}
      </span>
    </template>
  </button>
</template>
