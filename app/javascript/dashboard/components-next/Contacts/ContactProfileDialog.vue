<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import FintureCrmApi from 'dashboard/api/fintureCrm';
import ContactAPI from 'dashboard/api/contacts';
import { lostReasonLabel } from 'dashboard/routes/dashboard/kanban/config/stages';
import { summaryStateOf } from 'dashboard/routes/dashboard/kanban/helper/historyGrouping';
import {
  MEDIA_TYPES,
  NON_FILE_TYPES,
} from 'dashboard/components-next/message/constants';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Media from 'dashboard/components-next/SharedAttachments/Media.vue';
import Files from 'dashboard/components-next/SharedAttachments/Files.vue';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

// Perfil do cliente, centralizado: tudo de um contato em um lugar só.
// Cabeçalho com dados de contato, resumo geral gerado pela IA, agentes que já
// atenderam, e duas abas — Conversas (cada atendimento com datas, desfecho e
// resumo) e Anexos (mídias e arquivos trocados em qualquer conversa).
// Usado pelo Histórico do Kanban, pelo cabeçalho/painel da conversa e pela
// Gestão dos Clientes. Fontes: contacts/:id/finture_timeline e
// contacts/:id/attachments.
const props = defineProps({
  // Caixa ativa do Kanban: o reabrir recarrega o Histórico dela. Opcional.
  inboxId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const dialogRef = ref(null);
const contact = ref({});
const entries = ref([]);
const agents = ref([]);
const attachments = ref([]);
const isLoading = ref(false);
const isLoadingAttachments = ref(false);
const hasError = ref(false);
const reopeningId = ref(null);
const activeTab = ref('conversations');

const load = async contactId => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await FintureCrmApi.getContactTimeline(contactId);
    contact.value = { ...contact.value, ...data.contact };
    entries.value = data.payload || [];
    agents.value = data.agents || [];
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const loadAttachments = async contactId => {
  isLoadingAttachments.value = true;
  try {
    const { data } = await ContactAPI.getAttachments(contactId);
    attachments.value = data.payload || [];
  } catch {
    attachments.value = [];
  } finally {
    isLoadingAttachments.value = false;
  }
};

// `seed` é o contato de onde o modal foi aberto (nome/telefone aparecem na
// hora, antes da resposta da API).
const open = seed => {
  contact.value = seed || {};
  entries.value = [];
  agents.value = [];
  attachments.value = [];
  activeTab.value = 'conversations';
  dialogRef.value?.open();
  if (seed?.id) {
    load(seed.id);
    loadAttachments(seed.id);
  }
};

const close = () => dialogRef.value?.close();

const dateTimeFormatter = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});
const dateFormatter = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
});
const formatDateTime = epoch =>
  epoch ? dateTimeFormatter.format(new Date(epoch * 1000)) : '';
const formatDate = epoch =>
  epoch ? dateFormatter.format(new Date(epoch * 1000)) : '';

const accountId = computed(() => route.params.accountId);
const contactPageLink = computed(() =>
  contact.value.id
    ? `/app/accounts/${accountId.value}/contacts/${contact.value.id}`
    : ''
);

const location = computed(() =>
  [contact.value.city, contact.value.country].filter(Boolean).join(', ')
);

// Campos do cabeçalho. Telefone e e-mail aparecem sempre (mesmo vazios), o
// resto só quando preenchido.
const infoFields = computed(() => {
  const fields = [
    {
      key: 'phone',
      icon: 'i-lucide-phone',
      label: t('CONTACT_PROFILE.FIELDS.PHONE'),
      value: contact.value.phone_number,
      href: contact.value.phone_number
        ? `tel:${contact.value.phone_number}`
        : '',
      copy: true,
    },
    {
      key: 'email',
      icon: 'i-lucide-mail',
      label: t('CONTACT_PROFILE.FIELDS.EMAIL'),
      value: contact.value.email,
      href: contact.value.email ? `mailto:${contact.value.email}` : '',
      copy: true,
    },
    {
      key: 'company',
      icon: 'i-lucide-building-2',
      label: t('CONTACT_PROFILE.FIELDS.COMPANY'),
      value: contact.value.company_name,
    },
    {
      key: 'location',
      icon: 'i-lucide-map-pin',
      label: t('CONTACT_PROFILE.FIELDS.LOCATION'),
      value: location.value,
    },
    {
      key: 'identifier',
      icon: 'i-lucide-id-card',
      label: t('CONTACT_PROFILE.FIELDS.IDENTIFIER'),
      value: contact.value.identifier,
    },
    {
      key: 'since',
      icon: 'i-lucide-calendar',
      label: t('CONTACT_PROFILE.FIELDS.SINCE'),
      value: formatDate(contact.value.created_at),
    },
    {
      key: 'lastActivity',
      icon: 'i-lucide-activity',
      label: t('CONTACT_PROFILE.FIELDS.LAST_ACTIVITY'),
      value: formatDateTime(contact.value.last_activity_at),
    },
  ];
  return fields.filter(field => field.copy || field.value);
});

const copyValue = async value => {
  try {
    await copyTextToClipboard(String(value));
    useAlert(t('CONTACT_PROFILE.COPIED'));
  } catch {
    // sem clipboard disponível — ignora
  }
};

const closedCount = computed(
  () => entries.value.filter(entry => entry.closed_at).length
);
const openCount = computed(() => entries.value.length - closedCount.value);

const visibleAttachments = computed(() =>
  attachments.value.filter(
    a => a.data_url && !NON_FILE_TYPES.includes(a.file_type)
  )
);
const mediaAttachments = computed(() =>
  visibleAttachments.value
    .filter(a => MEDIA_TYPES.includes(a.file_type))
    .sort((a, b) => (b.created_at || 0) - (a.created_at || 0))
);

const tabs = computed(() => [
  {
    key: 'conversations',
    icon: 'i-lucide-messages-square',
    label: t('CONTACT_PROFILE.TABS.CONVERSATIONS', {
      count: entries.value.length,
    }),
  },
  {
    key: 'attachments',
    icon: 'i-lucide-paperclip',
    label: t('CONTACT_PROFILE.TABS.ATTACHMENTS', {
      count: visibleAttachments.value.length,
    }),
  },
]);

// Selo do atendimento: desfecho comercial > status da conversa.
const badgeOf = entry => {
  if (entry.outcome === 'won')
    return {
      label: t('KANBAN.OUTCOME.WON'),
      icon: 'i-lucide-trophy',
      class: 'bg-n-teal-3 text-n-teal-11',
      dot: 'bg-n-teal-9',
    };
  if (entry.outcome === 'lost')
    return {
      label: t('KANBAN.OUTCOME.LOST'),
      icon: 'i-lucide-circle-x',
      class: 'bg-n-ruby-3 text-n-ruby-11',
      dot: 'bg-n-ruby-9',
    };
  if (entry.closed_at)
    return {
      label: t('KANBAN.HISTORY.TIMELINE.RESOLVED'),
      icon: 'i-lucide-check-check',
      class: 'bg-n-slate-3 text-n-slate-11',
      dot: 'bg-n-slate-8',
    };
  return {
    label: t('KANBAN.HISTORY.TIMELINE.OPEN'),
    icon: 'i-lucide-circle-dot',
    class: 'bg-n-amber-3 text-n-amber-11',
    dot: 'bg-n-amber-9',
  };
};

// "#123 · Caixa · Responsável"
const entryMeta = entry =>
  [`#${entry.id}`, entry.inbox_name, entry.assignee_name]
    .filter(Boolean)
    .join(' · ');

// "Aberta em … · fechada em …"
const entryDates = entry => {
  const parts = [
    t('KANBAN.HISTORY.TIMELINE.OPENED_AT', {
      date: formatDateTime(entry.created_at),
    }),
  ];
  if (entry.closed_at)
    parts.push(
      t('KANBAN.HISTORY.TIMELINE.CLOSED_AT', {
        date: formatDateTime(entry.closed_at),
      })
    );
  return parts.join(' · ');
};

const summaryLabels = computed(() => ({
  pending: t('KANBAN.HISTORY.SUMMARY_PENDING'),
  missing: t('KANBAN.HISTORY.SUMMARY_MISSING'),
  open: t('KANBAN.HISTORY.SUMMARY_OPEN'),
}));

const nowSeconds = () => Math.round(Date.now() / 1000);
const summaryState = entry =>
  summaryStateOf({
    resumo: entry.resumo,
    closedAt: entry.closed_at,
    now: nowSeconds(),
  });

const openConversation = entry => {
  const path = frontendURL(
    conversationUrl({ accountId: accountId.value, id: entry.id })
  );
  close();
  router.push({ path });
};

const openContactPage = () => {
  close();
  router.push({ path: contactPageLink.value });
};

const reopen = async entry => {
  reopeningId.value = entry.id;
  try {
    await store.dispatch('kanban/reopenLead', {
      conversationId: entry.id,
      inboxId: props.inboxId,
    });
    await load(contact.value.id);
  } catch {
    useAlert(t('KANBAN.ERRORS.UPDATE_OUTCOME'));
  } finally {
    reopeningId.value = null;
  }
};

// Galeria de mídia (mesma usada nos anexos da conversa).
const showGallery = ref(false);
const selectedAttachment = ref(null);
const onMediaSelect = attachment => {
  selectedAttachment.value = attachment;
  showGallery.value = true;
};
const onFileSelect = attachment => {
  if (attachment.data_url) {
    window.open(attachment.data_url, '_blank', 'noopener,noreferrer');
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    :show-confirm-button="false"
    :cancel-button-label="t('KANBAN.HISTORY.TIMELINE.CLOSE')"
  >
    <div class="flex flex-col gap-4 -mt-2 [&_p]:mb-0">
      <!-- Cabeçalho: identidade + ações rápidas -->
      <header class="flex items-start gap-4">
        <Avatar
          :name="contact.name || ''"
          :src="contact.thumbnail || ''"
          :size="56"
          rounded-full
        />
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <div class="flex items-start justify-between gap-3">
            <h3
              class="text-lg font-semibold leading-tight truncate text-n-slate-12"
            >
              {{ contact.name || '—' }}
            </h3>
            <Button
              v-if="contactPageLink"
              type="button"
              color="slate"
              variant="ghost"
              size="xs"
              icon="i-lucide-external-link"
              class="shrink-0"
              :label="t('CONTACT_PROFILE.OPEN_CONTACT')"
              @click="openContactPage"
            />
          </div>
          <p
            v-if="contact.description"
            class="text-sm text-n-slate-11 line-clamp-2"
          >
            {{ contact.description }}
          </p>
          <!-- Pílulas de situação -->
          <div class="flex flex-wrap items-center gap-1.5 mt-1">
            <span
              class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              <Icon icon="i-lucide-messages-square" class="size-3" />
              {{
                t('CONTACT_PROFILE.STATS.CONVERSATIONS', {
                  count: entries.length,
                })
              }}
            </span>
            <span
              v-if="openCount"
              class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full bg-n-amber-3 text-n-amber-11"
            >
              <Icon icon="i-lucide-circle-dot" class="size-3" />
              {{ t('CONTACT_PROFILE.STATS.OPEN', { count: openCount }) }}
            </span>
            <span
              v-if="closedCount"
              class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-full bg-n-slate-3 text-n-slate-11"
            >
              <Icon icon="i-lucide-check-check" class="size-3" />
              {{ t('CONTACT_PROFILE.STATS.CLOSED', { count: closedCount }) }}
            </span>
          </div>
        </div>
      </header>

      <!-- Dados de contato -->
      <dl
        class="grid grid-cols-2 gap-x-4 gap-y-3 p-3 sm:grid-cols-3 rounded-xl bg-n-alpha-1"
      >
        <div
          v-for="field in infoFields"
          :key="field.key"
          class="flex flex-col min-w-0 gap-0.5"
        >
          <dt
            class="flex items-center gap-1 text-[11px] font-medium tracking-wide uppercase text-n-slate-10"
          >
            <Icon :icon="field.icon" class="size-3" />
            {{ field.label }}
          </dt>
          <dd class="flex items-center min-w-0 gap-1 text-sm text-n-slate-12">
            <a
              v-if="field.value && field.href"
              :href="field.href"
              class="truncate hover:underline text-n-slate-12"
            >
              {{ field.value }}
            </a>
            <span
              v-else
              class="truncate"
              :class="{ 'text-n-slate-10': !field.value }"
            >
              {{ field.value || t('CONTACT_PROFILE.FIELDS.EMPTY') }}
            </span>
            <button
              v-if="field.copy && field.value"
              type="button"
              class="flex items-center justify-center rounded shrink-0 size-5 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
              :title="t('CONTACT_PROFILE.COPY')"
              @click="copyValue(field.value)"
            >
              <Icon icon="i-lucide-copy" class="size-3" />
            </button>
          </dd>
        </div>
      </dl>

      <div v-if="isLoading && !entries.length" class="flex justify-center py-8">
        <Spinner />
      </div>
      <p v-else-if="hasError" class="py-6 text-sm text-center text-n-ruby-11">
        {{ t('KANBAN.HISTORY.TIMELINE.ERROR') }}
      </p>

      <div
        v-else
        class="flex flex-col gap-4 overflow-y-auto max-h-[52vh] ltr:pr-1 rtl:pl-1"
      >
        <!-- Resumo geral do cliente (rolante, todas as conversas) -->
        <section
          v-if="contact.resumo_atendimentos"
          class="flex flex-col gap-1.5 p-3 rounded-xl bg-n-alpha-1"
        >
          <span
            class="flex items-center gap-1.5 text-xs font-medium text-n-slate-11"
          >
            <Icon icon="i-lucide-sparkles" class="size-3.5" />
            {{ t('KANBAN.HISTORY.TIMELINE.CLIENT_SUMMARY') }}
          </span>
          <p class="text-sm whitespace-pre-line text-n-slate-12">
            {{ contact.resumo_atendimentos }}
          </p>
        </section>

        <!-- Agentes que já atenderam -->
        <section v-if="agents.length" class="flex flex-col gap-1.5">
          <span
            class="flex items-center gap-1.5 text-xs font-medium text-n-slate-11"
          >
            <Icon icon="i-lucide-users-round" class="size-3.5" />
            {{ t('CONTACT_PROFILE.AGENTS') }}
          </span>
          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="agent in agents"
              :key="agent.id"
              class="inline-flex items-center gap-1.5 py-1 pl-1 pr-2 text-xs font-medium rounded-full bg-n-blue-3 text-n-blue-11"
              :title="
                t('CONTACT_PROFILE.AGENT_LAST', {
                  date: formatDate(agent.last_at),
                })
              "
            >
              <Avatar
                :name="agent.name"
                :src="agent.thumbnail || ''"
                :size="18"
                rounded-full
              />
              {{ agent.name }}
              <span
                v-if="agent.count > 1"
                class="px-1 rounded-full bg-n-blue-5 text-n-blue-12 text-[10px]"
              >
                {{ agent.count }}
              </span>
            </span>
          </div>
        </section>

        <!-- Abas: Conversas / Anexos -->
        <div class="flex items-center gap-1 border-b border-n-weak">
          <button
            v-for="tab in tabs"
            :key="tab.key"
            type="button"
            class="inline-flex items-center gap-1.5 px-3 py-2 -mb-px text-sm border-b-2 transition-colors"
            :class="
              activeTab === tab.key
                ? 'border-n-brand text-n-slate-12 font-medium'
                : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
            "
            @click="activeTab = tab.key"
          >
            <Icon :icon="tab.icon" class="size-3.5" />
            {{ tab.label }}
          </button>
        </div>

        <!-- Aba Conversas: uma entrada por atendimento -->
        <section v-if="activeTab === 'conversations'" class="flex flex-col">
          <p
            v-if="!entries.length"
            class="py-6 text-sm text-center text-n-slate-11"
          >
            {{ t('CONTACT_PROFILE.NO_CONVERSATIONS') }}
          </p>
          <ol v-else class="flex flex-col">
            <li
              v-for="(entry, index) in entries"
              :key="entry.id"
              class="relative flex gap-3 ltr:pl-1 rtl:pr-1"
            >
              <div class="flex flex-col items-center pt-1.5">
                <span
                  class="rounded-full size-2.5 shrink-0"
                  :class="badgeOf(entry).dot"
                />
                <span
                  v-if="index < entries.length - 1"
                  class="flex-1 w-px mt-1 bg-n-weak"
                />
              </div>
              <div class="flex flex-col flex-1 min-w-0 gap-1.5 pb-4">
                <div class="flex flex-wrap items-center gap-2">
                  <span
                    class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md"
                    :class="badgeOf(entry).class"
                  >
                    <Icon :icon="badgeOf(entry).icon" class="size-3" />
                    {{ badgeOf(entry).label }}
                  </span>
                  <span class="text-xs text-n-slate-11">
                    {{ entryMeta(entry) }}
                  </span>
                </div>

                <p class="text-xs text-n-slate-11">{{ entryDates(entry) }}</p>

                <p
                  v-if="entry.outcome === 'lost' && entry.lost_reason"
                  class="text-xs text-n-slate-11"
                >
                  {{
                    t('KANBAN.HISTORY.TIMELINE.LOST_REASON', {
                      reason: lostReasonLabel(entry.lost_reason),
                    })
                  }}
                </p>

                <p
                  v-if="summaryState(entry) === 'ready'"
                  class="text-sm whitespace-pre-line text-n-slate-12"
                >
                  {{ entry.resumo }}
                </p>
                <p
                  v-else
                  class="flex items-center gap-1.5 text-xs italic text-n-slate-10"
                >
                  <Icon
                    v-if="summaryState(entry) === 'pending'"
                    icon="i-lucide-loader"
                    class="size-3.5"
                  />
                  {{ summaryLabels[summaryState(entry)] }}
                </p>

                <div class="flex items-center gap-1 -ml-2 rtl:-mr-2 rtl:ml-0">
                  <Button
                    type="button"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    icon="i-lucide-message-circle"
                    :label="t('KANBAN.HISTORY.TIMELINE.OPEN_CONVERSATION')"
                    @click="openConversation(entry)"
                  />
                  <Button
                    v-if="entry.outcome"
                    type="button"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    icon="i-lucide-rotate-ccw"
                    :label="t('KANBAN.OUTCOME.REOPEN')"
                    :is-loading="reopeningId === entry.id"
                    @click="reopen(entry)"
                  />
                </div>
              </div>
            </li>
          </ol>
        </section>

        <!-- Aba Anexos: mídias e arquivos de todas as conversas -->
        <section v-else class="flex flex-col gap-5">
          <div v-if="isLoadingAttachments" class="flex justify-center py-6">
            <Spinner class="size-5" />
          </div>
          <p
            v-else-if="!visibleAttachments.length"
            class="py-6 text-sm text-center text-n-slate-11"
          >
            {{ t('CONVERSATION_SIDEBAR.SHARED_FILES.EMPTY') }}
          </p>
          <template v-else>
            <Media :attachments="visibleAttachments" @select="onMediaSelect" />
            <Files :attachments="visibleAttachments" @select="onFileSelect" />
          </template>
        </section>
      </div>
    </div>
    <GalleryView
      v-if="showGallery && selectedAttachment"
      v-model:show="showGallery"
      :attachment="selectedAttachment"
      :all-attachments="mediaAttachments"
      auto-play
      @close="showGallery = false"
    />
  </Dialog>
</template>
