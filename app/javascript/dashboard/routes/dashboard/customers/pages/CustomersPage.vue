<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';

import ContactProfileDialog from 'dashboard/components-next/Contacts/ContactProfileDialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

// Gestão dos Clientes: uma barra de busca (nome, telefone ou e-mail) e, para
// cada cliente encontrado, uma linha que abre o perfil completo (mesmo modal
// do Histórico do Kanban e do cabeçalho da conversa).
const { t } = useI18n();

const MIN_QUERY_LENGTH = 2;
const DEBOUNCE_MS = 350;

const query = ref('');
const results = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const hasSearched = ref(false);
const dialogRef = ref(null);

let debounceTimer = null;
let abortController = null;

const normalizedQuery = computed(() => query.value.trim());
const canSearch = computed(
  () => normalizedQuery.value.length >= MIN_QUERY_LENGTH
);

const search = async () => {
  if (!canSearch.value) {
    results.value = [];
    hasSearched.value = false;
    return;
  }
  abortController?.abort();
  abortController = new AbortController();
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await ContactAPI.search(
      normalizedQuery.value,
      1,
      'name',
      '',
      { signal: abortController.signal }
    );
    results.value = data.payload || [];
    hasSearched.value = true;
  } catch (error) {
    if (error?.name === 'CanceledError' || error?.code === 'ERR_CANCELED')
      return;
    hasError.value = true;
    results.value = [];
    hasSearched.value = true;
  } finally {
    isLoading.value = false;
  }
};

watch(query, () => {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(search, DEBOUNCE_MS);
});

onBeforeUnmount(() => {
  clearTimeout(debounceTimer);
  abortController?.abort();
});

const submit = () => {
  clearTimeout(debounceTimer);
  search();
};

const clear = () => {
  query.value = '';
  results.value = [];
  hasSearched.value = false;
};

const dateFormatter = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
});
const formatDate = epoch =>
  epoch ? dateFormatter.format(new Date(epoch * 1000)) : '';

const contactMeta = contact =>
  [contact.phone_number, contact.email].filter(Boolean).join(' · ');

const openContact = contact => {
  dialogRef.value?.open({ ...contact });
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center justify-between flex-shrink-0 gap-4 px-6 py-2.5 border-b border-n-weak"
    >
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('CUSTOMERS.HEADER_TITLE') }}
      </h1>
    </header>

    <div class="flex flex-col flex-1 min-h-0 gap-5 px-6 py-6 overflow-hidden">
      <!-- Busca -->
      <form
        class="flex flex-col w-full max-w-2xl gap-2 mx-auto"
        @submit.prevent="submit"
      >
        <label
          class="relative flex items-center w-full h-12 gap-2 px-4 transition-colors rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak focus-within:outline-n-brand"
        >
          <Icon
            icon="i-lucide-search"
            class="size-5 shrink-0 text-n-slate-10"
          />
          <input
            v-model="query"
            type="text"
            class="flex-1 h-full text-base bg-transparent border-0 outline-none reset-base text-n-slate-12 placeholder:text-n-slate-10 !mb-0"
            :placeholder="t('CUSTOMERS.SEARCH_PLACEHOLDER')"
            autocomplete="off"
            autofocus
          />
          <Spinner v-if="isLoading" class="size-4 shrink-0" />
          <button
            v-else-if="query"
            type="button"
            class="flex items-center justify-center rounded-md shrink-0 size-6 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
            :title="t('CUSTOMERS.CLEAR')"
            @click="clear"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </label>
        <p class="text-xs text-center text-n-slate-10">
          {{ t('CUSTOMERS.SEARCH_HINT') }}
        </p>
      </form>

      <!-- Resultados -->
      <div class="flex flex-col flex-1 w-full max-w-2xl min-h-0 mx-auto">
        <EmptyStateLayout
          v-if="!hasSearched && !isLoading"
          class="flex-1 min-h-0"
          :title="t('CUSTOMERS.IDLE_TITLE')"
          :subtitle="t('CUSTOMERS.IDLE_SUBTITLE')"
          :show-backdrop="false"
        />
        <p v-else-if="hasError" class="py-6 text-sm text-center text-n-ruby-11">
          {{ t('CUSTOMERS.ERROR') }}
        </p>
        <EmptyStateLayout
          v-else-if="hasSearched && !results.length && !isLoading"
          class="flex-1 min-h-0"
          :title="t('CUSTOMERS.EMPTY_TITLE')"
          :subtitle="t('CUSTOMERS.EMPTY_SUBTITLE')"
          :show-backdrop="false"
        />
        <template v-else-if="results.length">
          <span class="mb-2 text-xs font-medium text-n-slate-11">
            {{ t('CUSTOMERS.RESULTS_COUNT', { count: results.length }) }}
          </span>
          <ul
            class="flex flex-col flex-1 min-h-0 gap-2 overflow-y-auto [&_p]:mb-0"
          >
            <li v-for="contact in results" :key="contact.id">
              <button
                type="button"
                class="flex items-center w-full gap-3 p-3 transition-colors rounded-xl text-start bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak hover:bg-n-alpha-1"
                @click="openContact(contact)"
              >
                <Avatar
                  :name="contact.name || ''"
                  :src="contact.thumbnail || ''"
                  :size="36"
                  rounded-full
                />
                <div class="flex flex-col flex-1 min-w-0 gap-0.5">
                  <span class="text-sm font-medium truncate text-n-slate-12">
                    {{ contact.name || '—' }}
                  </span>
                  <span
                    v-if="contactMeta(contact)"
                    class="text-xs truncate text-n-slate-11"
                  >
                    {{ contactMeta(contact) }}
                  </span>
                </div>
                <span
                  v-if="contact.last_activity_at"
                  class="text-xs shrink-0 text-n-slate-10"
                  :title="t('CONTACT_PROFILE.FIELDS.LAST_ACTIVITY')"
                >
                  {{ formatDate(contact.last_activity_at) }}
                </span>
                <Icon
                  icon="i-lucide-chevron-right"
                  class="size-4 shrink-0 text-n-slate-10"
                />
              </button>
            </li>
          </ul>
        </template>
      </div>
    </div>

    <ContactProfileDialog ref="dialogRef" />
  </section>
</template>
