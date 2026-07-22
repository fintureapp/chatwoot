<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  QUOTE_PRODUCTS,
  ANS_AGE_BANDS,
  quoteProduct,
} from 'dashboard/routes/dashboard/kanban/config/quoteProducts';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    default: null,
  },
});

const store = useStore();
const { t } = useI18n();

const getQuote = useMapGetter('kanban/getQuote');
const uiFlags = useMapGetter('kanban/getQuoteUIFlags');

const quote = computed(() =>
  props.conversationId ? getQuote.value(props.conversationId) : null
);

const editing = ref(false);
const draft = ref({ product_type: 'saude_pme', total_value: null, data: {} });

const productConfig = computed(() => quoteProduct(draft.value.product_type));

const formatMoney = value =>
  Number(value).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

// Linhas de leitura da cotação salva (só campos preenchidos).
const summaryRows = computed(() => {
  if (!quote.value) return [];
  const config = quoteProduct(quote.value.product_type);
  if (!config) return [];
  const rows = [];
  const data = quote.value.data || {};
  config.fields.forEach(field => {
    const raw = data[field.key];
    if (raw === undefined || raw === null || raw === '') return;
    let value = raw;
    if (field.type === 'boolean') {
      value = raw ? t('KANBAN.QUOTE.YES') : t('KANBAN.QUOTE.NO');
    } else if (field.type === 'select') {
      const option = field.options.find(item => item.value === raw);
      value = option ? t(option.labelKey) : raw;
    } else if (field.type === 'lives') {
      const total = Object.values(raw).reduce(
        (sum, qty) => sum + Number(qty || 0),
        0
      );
      if (!total) return;
      value = t('KANBAN.QUOTE.LIVES_TOTAL', { total });
    }
    rows.push({ key: field.key, label: t(field.labelKey), value });
  });
  if (quote.value.total_value) {
    rows.push({
      key: 'total_value',
      label: t(config.totalValueLabelKey),
      value: formatMoney(quote.value.total_value),
    });
  }
  return rows;
});

const startEdit = () => {
  const existing = quote.value;
  draft.value = {
    product_type: existing?.product_type || 'saude_pme',
    total_value: existing?.total_value ?? null,
    data: JSON.parse(JSON.stringify(existing?.data || {})),
  };
  if (!draft.value.data.lives) draft.value.data.lives = {};
  editing.value = true;
};

const save = async () => {
  const payload = {
    product_type: draft.value.product_type,
    data: { ...draft.value.data },
    total_value: draft.value.total_value || null,
  };
  // Faixas vazias/zeradas ficam fora do jsonb (mapa esparso, como o backend espera).
  payload.data.lives = Object.fromEntries(
    Object.entries(payload.data.lives || {}).filter(
      ([, qty]) => Number(qty) > 0
    )
  );
  try {
    await store.dispatch('kanban/saveQuote', {
      conversationId: props.conversationId,
      quote: payload,
    });
    editing.value = false;
  } catch {
    useAlert(t('KANBAN.QUOTE.SAVE_ERROR'));
  }
};

watch(
  () => props.conversationId,
  conversationId => {
    editing.value = false;
    if (conversationId) {
      store.dispatch('kanban/fetchQuote', { conversationId });
    }
  },
  { immediate: true }
);
</script>

<template>
  <section class="flex flex-col gap-2">
    <div class="flex items-center justify-between">
      <h3 class="text-xs font-semibold tracking-wide uppercase text-n-slate-10">
        {{ $t('KANBAN.QUOTE.TITLE') }}
      </h3>
      <button
        v-if="!editing && !uiFlags.isFetching"
        class="text-xs text-n-brand hover:underline"
        @click="startEdit"
      >
        {{ quote ? $t('KANBAN.DRAWER.EDIT') : $t('KANBAN.DRAWER.ADD') }}
      </button>
    </div>

    <div
      v-if="uiFlags.isFetching"
      class="flex items-center justify-center py-4 text-n-slate-11"
    >
      <Spinner />
    </div>

    <!-- Formulário -->
    <div v-else-if="editing" class="flex flex-col gap-3">
      <!-- Produto -->
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="product in QUOTE_PRODUCTS"
          :key="product.value"
          class="px-2.5 h-7 text-xs rounded-full border"
          :class="
            draft.product_type === product.value
              ? 'border-n-brand text-n-brand bg-n-brand/10'
              : 'border-n-weak text-n-slate-11 hover:text-n-slate-12'
          "
          @click="draft.product_type = product.value"
        >
          {{ $t(product.labelKey) }}
        </button>
      </div>

      <!-- Campos do produto -->
      <div
        v-for="field in productConfig.fields"
        :key="field.key"
        class="flex flex-col gap-1"
      >
        <label class="text-xs text-n-slate-11">{{ $t(field.labelKey) }}</label>

        <select
          v-if="field.type === 'select'"
          v-model="draft.data[field.key]"
          class="h-8 px-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12"
        >
          <option :value="undefined">—</option>
          <option
            v-for="option in field.options"
            :key="option.value"
            :value="option.value"
          >
            {{ $t(option.labelKey) }}
          </option>
        </select>

        <div v-else-if="field.type === 'boolean'" class="flex gap-3 text-sm">
          <label class="flex items-center gap-1.5">
            <input
              v-model="draft.data[field.key]"
              type="radio"
              :name="field.key"
              :value="true"
            />
            {{ $t('KANBAN.QUOTE.YES') }}
          </label>
          <label class="flex items-center gap-1.5">
            <input
              v-model="draft.data[field.key]"
              type="radio"
              :name="field.key"
              :value="false"
            />
            {{ $t('KANBAN.QUOTE.NO') }}
          </label>
        </div>

        <!-- Vidas por faixa etária ANS -->
        <div
          v-else-if="field.type === 'lives'"
          class="grid grid-cols-2 gap-x-4 gap-y-1"
        >
          <div
            v-for="band in ANS_AGE_BANDS"
            :key="band"
            class="flex items-center justify-between gap-2"
          >
            <span class="text-xs text-n-slate-11">{{ band }}</span>
            <input
              v-model.number="draft.data.lives[band]"
              type="number"
              min="0"
              :placeholder="$t('KANBAN.QUOTE.PLACEHOLDER_ZERO')"
              class="w-14 h-7 px-1.5 text-sm text-center border rounded-md bg-n-background border-n-weak text-n-slate-12"
            />
          </div>
        </div>

        <textarea
          v-else-if="field.type === 'textarea'"
          v-model="draft.data[field.key]"
          rows="2"
          :maxlength="1000"
          class="w-full px-3 py-2 text-sm border rounded-lg resize-none bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        />

        <input
          v-else
          v-model="draft.data[field.key]"
          :type="field.type === 'number' ? 'number' : 'text'"
          class="h-8 px-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        />
      </div>

      <!-- Valor principal do produto (vira sugestão de valor_potencial no backend) -->
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">
          {{ $t(productConfig.totalValueLabelKey) }}
        </label>
        <input
          v-model.number="draft.total_value"
          type="number"
          min="0"
          step="0.01"
          :placeholder="$t('KANBAN.QUOTE.PLACEHOLDER_MONEY')"
          class="h-8 px-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        />
      </div>

      <div class="flex items-center gap-2">
        <button
          class="px-3 h-8 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
          :disabled="uiFlags.isSaving"
          @click="save"
        >
          {{ $t('KANBAN.DRAWER.SAVE') }}
        </button>
        <button
          class="px-3 h-8 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
          @click="editing = false"
        >
          {{ $t('KANBAN.DRAWER.CANCEL') }}
        </button>
      </div>
    </div>

    <!-- Leitura -->
    <template v-else-if="quote">
      <dl class="flex flex-col gap-2">
        <div class="flex items-start gap-3 text-sm">
          <dt class="w-32 shrink-0 text-n-slate-11">
            {{ $t('KANBAN.QUOTE.PRODUCT') }}
          </dt>
          <dd class="min-w-0 break-words text-n-slate-12">
            {{ $t(quoteProduct(quote.product_type)?.labelKey) }}
            <span
              v-if="quote.source === 'n8n'"
              class="ml-1 px-1.5 py-0.5 text-[10px] rounded bg-n-alpha-2 text-n-slate-11"
              :title="$t('KANBAN.QUOTE.SOURCE_N8N')"
            >
              <Icon icon="i-lucide-bot" class="inline size-3" />
              {{ $t('KANBAN.QUOTE.SOURCE_BADGE') }}
            </span>
          </dd>
        </div>
        <div
          v-for="row in summaryRows"
          :key="row.key"
          class="flex items-start gap-3 text-sm"
        >
          <dt class="w-32 shrink-0 text-n-slate-11">{{ row.label }}</dt>
          <dd class="min-w-0 break-words text-n-slate-12">{{ row.value }}</dd>
        </div>
      </dl>
    </template>

    <p v-else class="text-sm italic text-n-slate-10">
      {{ $t('KANBAN.QUOTE.EMPTY') }}
    </p>
  </section>
</template>
