<script setup>
// Bloco da Home: título + uma linha dizendo de que recorte os números são
// (estoque agora, eventos do período ou coorte de entrada).
defineProps({
  title: { type: String, required: true },
  note: { type: String, default: '' },
});
</script>

<template>
  <section class="flex flex-col gap-3">
    <header class="flex flex-col gap-0.5">
      <h2 class="text-sm font-semibold text-n-slate-12">{{ title }}</h2>
      <p v-if="note" class="text-xs text-n-slate-11">{{ note }}</p>
    </header>
    <slot />
  </section>
</template>
