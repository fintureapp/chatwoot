<script setup>
// Agenda de follow-ups do próprio agente (rodapé das duas visões do Dashboard
// SDR): o que ele marcou, ordenado por vencimento, com os vencidos em destaque.
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  items: { type: Array, default: () => [] },
});

const { t } = useI18n();

const dueLabel = epoch => {
  const date = new Date(epoch * 1000);
  const day = date.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });
  const time = date.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
  return `${day} ${time}`;
};
</script>

<template>
  <div
    class="flex flex-col gap-4 p-4 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
  >
    <div>
      <div
        class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
      >
        {{ t('KANBAN.DASHBOARD.MY_FOLLOWUPS_EYEBROW') }}
      </div>
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.DASHBOARD.MY_FOLLOWUPS_TITLE') }}
      </h3>
    </div>
    <ul v-if="items.length" class="flex flex-col divide-y divide-n-weak">
      <li
        v-for="item in items"
        :key="item.id"
        class="flex items-center justify-between gap-3 py-2 first:pt-0"
      >
        <div class="min-w-0">
          <div class="text-[13px] font-medium truncate text-n-slate-12">
            {{ item.contact || t('KANBAN.DASHBOARD.NOT_INFORMED') }}
          </div>
          <div v-if="item.title" class="text-xs truncate text-n-slate-11">
            {{ item.title }}
          </div>
        </div>
        <span
          class="flex items-center gap-1 text-xs whitespace-nowrap tabular-nums"
          :class="
            item.overdue ? 'text-n-ruby-11 font-semibold' : 'text-n-slate-11'
          "
        >
          <Icon icon="i-lucide-clock" class="size-3.5" />
          {{ dueLabel(item.due_at) }}
        </span>
      </li>
    </ul>
    <p v-else class="text-sm text-n-slate-10">
      {{ t('KANBAN.DASHBOARD.MY_FOLLOWUPS_EMPTY') }}
    </p>
  </div>
</template>
