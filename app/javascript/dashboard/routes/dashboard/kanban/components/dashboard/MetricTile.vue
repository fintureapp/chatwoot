<script setup>
// Cartão de KPI do Dashboard SDR: rótulo + ícone, valor em destaque e um chip de
// variação (delta) com tom semântico. Componente "burro": o pai já formata
// `value` e `delta.text`; aqui só renderiza.
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  icon: { type: String, default: '' },
  // { text: '+9%', tone: 'good' | 'bad' | 'neutral', hint?: 'vs mês ant.' }
  delta: { type: Object, default: null },
  // 'default' | 'crit' | 'warn' — realça o valor (usado na visão operacional)
  emphasis: { type: String, default: 'default' },
});
</script>

<template>
  <div
    class="flex flex-col gap-2 p-4 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak min-h-[104px]"
  >
    <div class="flex items-center gap-1.5 text-n-slate-11">
      <Icon v-if="icon" :icon="icon" class="size-4" />
      <span class="text-xs">{{ label }}</span>
    </div>
    <span
      class="text-[28px] font-semibold leading-none tracking-tight tabular-nums"
      :class="{
        'text-n-slate-12': emphasis === 'default',
        'text-n-ruby-11': emphasis === 'crit',
        'text-n-amber-11': emphasis === 'warn',
      }"
    >
      {{ value }}
    </span>
    <span
      v-if="delta"
      class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full w-fit"
      :class="{
        'text-n-teal-11 bg-n-teal-3': delta.tone === 'good',
        'text-n-ruby-11 bg-n-ruby-3': delta.tone === 'bad',
        'text-n-slate-11 bg-n-alpha-2': delta.tone === 'neutral',
      }"
    >
      <Icon
        v-if="delta.tone === 'good'"
        icon="i-lucide-arrow-up-right"
        class="size-3"
      />
      <Icon
        v-else-if="delta.tone === 'bad'"
        icon="i-lucide-arrow-down-right"
        class="size-3"
      />
      {{ delta.text }}
      <span v-if="delta.hint" class="ml-0.5 font-normal text-n-slate-10">{{
        delta.hint
      }}</span>
    </span>
  </div>
</template>
