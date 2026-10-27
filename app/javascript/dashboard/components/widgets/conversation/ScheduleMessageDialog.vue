<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TemplatesPicker from './WhatsappTemplates/TemplatesPicker.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

// Agendar (ou editar o agendamento de) uma mensagem da conversa. Data/hora são
// hora de parede em America/Sao_Paulo — o servidor interpreta nesse fuso, então
// o resultado não depende do fuso do navegador do operador.
// Conteúdo: texto escrito pelo operador OU template aprovado do WhatsApp — o
// template é o que permite agendar para depois que a janela de 24h fecha.
const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const emit = defineEmits(['scheduled', 'updated']);

const TIMEZONE = 'America/Sao_Paulo';
const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const editing = ref(null); // item existente (edição) ou null (novo)
const content = ref('');
const date = ref('');
const time = ref('');
const cancelOnReply = ref(true);
const error = ref('');
const kind = ref('text'); // 'text' | 'template'
const selectedTemplate = ref(null);
const parserRef = ref(null);
// Variáveis já preenchidas de um agendamento em edição, aplicadas quando o
// formulário do template monta (ele se reinicializa a partir do template).
const paramsToRestore = ref(null);

const templates = computed(() =>
  props.inboxId
    ? store.getters['inboxes/getFilteredWhatsAppTemplates'](props.inboxId)
    : []
);
const hasTemplates = computed(() => templates.value.length > 0);
const inbox = computed(() =>
  props.inboxId ? store.getters['inboxes/getInbox'](props.inboxId) : {}
);
// WhatsApp oficial mostra o seletor mesmo vazio (ele tem o botão de sincronizar
// templates); nas demais caixas sem template a aba explica por que não há opção.
const canUseTemplates = computed(
  () => hasTemplates.value || inbox.value?.channel_type === 'Channel::Whatsapp'
);
const isTemplate = computed(() => kind.value === 'template');

const isSaving = computed(
  () => store.getters['fintureScheduledMessages/getUIFlags'].isSaving
);
const meta = computed(() =>
  store.getters['fintureScheduledMessages/getMeta'](props.conversationId)
);

// "YYYY-MM-DDTHH:mm" de um instante, na hora de parede de São Paulo.
const toLocalWall = instant => {
  const parts = new Intl.DateTimeFormat('sv-SE', {
    timeZone: TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(instant);
  return parts.replace(' ', 'T');
};

const nowWall = () => toLocalWall(new Date());
const scheduledWall = computed(() =>
  date.value && time.value ? `${date.value}T${time.value}` : ''
);

const labelFormatter = new Intl.DateTimeFormat('pt-BR', {
  timeZone: TIMEZONE,
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

// Aviso da janela do canal (WhatsApp 24h etc.), calculado pelo servidor.
const windowWarning = computed(() => {
  if (isTemplate.value) return '';
  const closesAt = meta.value?.messaging_window_closes_at;
  if (!closesAt || !scheduledWall.value) return '';
  const closesWall = toLocalWall(new Date(closesAt));
  if (closesWall < nowWall())
    return t('CONVERSATION.SCHEDULE.WINDOW_CLOSED_WARNING');
  if (scheduledWall.value > closesWall) {
    return t('CONVERSATION.SCHEDULE.WINDOW_WARNING', {
      time: labelFormatter.format(new Date(closesAt)),
    });
  }
  return '';
});

const findTemplate = ({ name, language }) =>
  templates.value.find(
    template =>
      template.name === name && (!language || template.language === language)
  ) || null;

const setKind = value => {
  kind.value = value;
  error.value = '';
};

const pickTemplate = template => {
  selectedTemplate.value = template;
  error.value = '';
};

const resetTemplate = () => {
  selectedTemplate.value = null;
  paramsToRestore.value = null;
};

watch(parserRef, parser => {
  if (!parser || !paramsToRestore.value) return;
  parser.processedParams = JSON.parse(JSON.stringify(paramsToRestore.value));
  paramsToRestore.value = null;
});

const openForItem = item => {
  content.value = item.kind === 'template' ? '' : item.content;
  [date.value, time.value] = item.scheduled_at_local.split('T');
  cancelOnReply.value = item.cancel_on_reply;
  kind.value = item.kind === 'template' ? 'template' : 'text';
  if (item.kind !== 'template') return;
  selectedTemplate.value = findTemplate(item.template_params || {});
  if (selectedTemplate.value) {
    paramsToRestore.value = item.template_params?.processed_params || null;
  } else {
    error.value = t('CONVERSATION.SCHEDULE.TEMPLATE_NOT_FOUND', {
      name: item.template_params?.name || '',
    });
  }
};

// `preferTemplate`: a caixa de resposta pede quando a janela já está fechada.
const open = ({ message = '', item = null, preferTemplate = false } = {}) => {
  editing.value = item;
  error.value = '';
  selectedTemplate.value = null;
  paramsToRestore.value = null;
  if (item) {
    openForItem(item);
  } else {
    content.value = message;
    // Sugestão: daqui a 1 hora (hora de São Paulo).
    const suggestion = toLocalWall(new Date(Date.now() + 60 * 60 * 1000));
    [date.value, time.value] = suggestion.split('T');
    cancelOnReply.value = true;
    kind.value = preferTemplate && canUseTemplates.value ? 'template' : 'text';
  }
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const validate = () => {
  if (!scheduledWall.value || scheduledWall.value <= nowWall()) {
    return t('CONVERSATION.SCHEDULE.PAST_ERROR');
  }
  if (isTemplate.value) {
    return selectedTemplate.value
      ? ''
      : t('CONVERSATION.SCHEDULE.TEMPLATE_REQUIRED');
  }
  if (!content.value.trim()) return t('CONVERSATION.SCHEDULE.EMPTY_ERROR');
  return '';
};

const save = async ({ messageContent, templateParams }) => {
  const payload = {
    content: messageContent,
    template_params: templateParams,
    scheduled_at: scheduledWall.value,
    cancel_on_reply: cancelOnReply.value,
  };
  try {
    if (editing.value) {
      const item = await store.dispatch('fintureScheduledMessages/update', {
        conversationId: props.conversationId,
        id: editing.value.id,
        payload,
      });
      useAlert(
        t('CONVERSATION.SCHEDULE.UPDATED', { time: item.scheduled_at_label })
      );
      emit('updated', item);
    } else {
      const item = await store.dispatch('fintureScheduledMessages/create', {
        conversationId: props.conversationId,
        payload,
      });
      useAlert(
        t('CONVERSATION.SCHEDULE.SUCCESS', { time: item.scheduled_at_label })
      );
      emit('scheduled', item);
    }
    close();
  } catch (e) {
    error.value =
      e?.response?.data?.message ||
      e?.response?.data?.error ||
      t('CONVERSATION.SCHEDULE.ERROR');
  }
};

// O formulário do template emite o mesmo payload que a caixa de resposta usa
// ({ message, templateParams }). Ele só barra variável vazia desabilitando o
// botão dele (que aqui não existe), então a checagem é refeita aqui.
const hasEmptyParam = ({ body = {}, header, buttons = [] } = {}) =>
  Object.values(body).some(value => !String(value ?? '').trim()) ||
  (!!header && 'media_url' in header && !header.media_url) ||
  buttons.some(button => !button.parameter);

const onTemplatePayload = ({ message, templateParams }) => {
  if (hasEmptyParam(templateParams.processed_params)) {
    error.value = t('CONVERSATION.SCHEDULE.TEMPLATE_PARAMS_ERROR');
    return;
  }
  save({ messageContent: message, templateParams });
};

const submit = async () => {
  error.value = validate();
  if (error.value) return;
  if (!isTemplate.value) {
    await save({ messageContent: content.value, templateParams: null });
    return;
  }
  await nextTick();
  parserRef.value?.sendMessage();
};

defineExpose({ open, close });

const tabClass = active =>
  active
    ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
    : 'text-n-slate-11 hover:text-n-slate-12';

const inputClass =
  'h-9 px-2.5 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      editing
        ? t('CONVERSATION.SCHEDULE.EDIT_TITLE')
        : t('CONVERSATION.SCHEDULE.TITLE')
    "
    :confirm-button-label="
      editing
        ? t('CONVERSATION.SCHEDULE.SAVE')
        : t('CONVERSATION.SCHEDULE.CONFIRM')
    "
    :cancel-button-label="t('CONVERSATION.SCHEDULE.CANCEL')"
    :is-loading="isSaving"
    :disable-confirm-button="isSaving"
    :width="isTemplate ? 'xl' : 'lg'"
    overflow-y-auto
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <div class="flex p-0.5 rounded-lg bg-n-alpha-2 w-fit" role="tablist">
        <button
          type="button"
          role="tab"
          :aria-selected="!isTemplate"
          class="px-3 py-1 text-sm rounded-md"
          :class="tabClass(!isTemplate)"
          @click="setKind('text')"
        >
          {{ t('CONVERSATION.SCHEDULE.KIND_TEXT') }}
        </button>
        <button
          type="button"
          role="tab"
          :aria-selected="isTemplate"
          class="px-3 py-1 text-sm rounded-md"
          :class="tabClass(isTemplate)"
          @click="setKind('template')"
        >
          {{ t('CONVERSATION.SCHEDULE.KIND_TEMPLATE') }}
        </button>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION.SCHEDULE.DATE') }}
          <input v-model="date" type="date" :class="inputClass" />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION.SCHEDULE.TIME') }}
          <input v-model="time" type="time" :class="inputClass" />
        </label>
      </div>
      <p class="text-xs text-n-slate-10">
        {{ t('CONVERSATION.SCHEDULE.TIMEZONE_NOTE') }}
      </p>

      <p
        v-if="isTemplate && !canUseTemplates"
        class="px-3 py-2 text-sm rounded-lg bg-n-amber-3 text-n-amber-12"
      >
        {{ t('CONVERSATION.SCHEDULE.NO_TEMPLATES', { inbox: inbox?.name }) }}
      </p>
      <template v-else-if="isTemplate">
        <p class="px-3 py-2 text-xs rounded-lg bg-n-teal-3 text-n-teal-12">
          {{ t('CONVERSATION.SCHEDULE.TEMPLATE_NOTE') }}
        </p>
        <TemplatesPicker
          v-if="!selectedTemplate"
          :inbox-id="inboxId"
          @on-select="pickTemplate"
        />
        <WhatsAppTemplateParser
          v-else
          ref="parserRef"
          :template="selectedTemplate"
          @send-message="onTemplatePayload"
          @reset-template="resetTemplate"
        >
          <template #actions="{ resetTemplate: changeTemplate }">
            <button
              type="button"
              class="text-xs underline text-n-slate-11 hover:text-n-slate-12"
              @click="changeTemplate"
            >
              {{ t('CONVERSATION.SCHEDULE.CHANGE_TEMPLATE') }}
            </button>
          </template>
        </WhatsAppTemplateParser>
      </template>

      <label v-else class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('CONVERSATION.SCHEDULE.PREVIEW') }}
        <textarea
          v-model="content"
          rows="5"
          class="px-2.5 py-2 text-sm border rounded-lg resize-y bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        />
      </label>

      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <input v-model="cancelOnReply" type="checkbox" class="mt-1" />
        <span>{{ t('CONVERSATION.SCHEDULE.CANCEL_ON_REPLY') }}</span>
      </label>

      <p
        v-if="windowWarning"
        class="px-3 py-2 text-xs rounded-lg bg-n-amber-3 text-n-amber-12"
      >
        {{ windowWarning }}
        <button
          v-if="canUseTemplates"
          type="button"
          class="font-medium underline ltr:ml-1 rtl:mr-1"
          @click="setKind('template')"
        >
          {{ t('CONVERSATION.SCHEDULE.USE_TEMPLATE') }}
        </button>
      </p>

      <p class="text-xs leading-snug text-n-slate-10">
        {{ t('CONVERSATION.SCHEDULE.POLICY_NOTE') }}
      </p>

      <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
    </div>
  </Dialog>
</template>
