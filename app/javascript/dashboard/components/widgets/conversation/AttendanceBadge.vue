<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Selo compacto de quem conduz a conversa (lista e kanban): robô = IA,
// pessoa = humano. Só aparece em caixas com atendimento por IA ligado.
const props = defineProps({
  attendance: { type: Object, default: null },
});

const { t } = useI18n();

const isVisible = computed(() => !!props.attendance?.ai_enabled);
const isAi = computed(() => props.attendance?.mode === 'ia');
const tooltip = computed(() =>
  isAi.value
    ? t('CONVERSATION.ATTENDANCE.AI_ATTENDING')
    : t('CONVERSATION.ATTENDANCE.HUMAN_ATTENDING')
);
</script>

<template>
  <span
    v-if="isVisible"
    v-tooltip="tooltip"
    :aria-label="tooltip"
    class="inline-block flex-shrink-0 size-3.5 align-[-2px]"
    :class="
      isAi
        ? 'i-lucide-bot text-n-blue-11'
        : 'i-lucide-user-round text-n-slate-11'
    "
  />
</template>
