<script setup>
import { computed, ref } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownContainer from 'dashboard/components-next/dropdown-menu/base/DropdownContainer.vue';
import DropdownBody from 'dashboard/components-next/dropdown-menu/base/DropdownBody.vue';
import DropdownSection from 'dashboard/components-next/dropdown-menu/base/DropdownSection.vue';
import DropdownItem from 'dashboard/components-next/dropdown-menu/base/DropdownItem.vue';

// Um filtro da barra "Filtros", em formato de pílula: mostra o nome do filtro
// (ou o que foi escolhido) e abre a lista de opções com seleção múltipla.
// Opções: { id, name, icon?, color? }. Listas longas ganham uma busca.
const props = defineProps({
  label: { type: String, required: true },
  icon: { type: String, default: '' },
  options: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  disabledHint: { type: String, default: '' },
  emptyHint: { type: String, default: '' },
  searchPlaceholder: { type: String, default: '' },
});

const selected = defineModel({ type: Array, default: () => [] });

const SEARCH_THRESHOLD = 8;
const search = ref('');

const selectedOptions = computed(() =>
  props.options.filter(option => selected.value.includes(option.id))
);
const selectedNames = computed(() =>
  selectedOptions.value.map(option => option.name)
);
// Com uma opção escolhida que tem ícone (ex.: WhatsApp), a pílula usa o dela.
const triggerIcon = computed(
  () => selectedOptions.value[0]?.icon || props.icon
);

const triggerLabel = computed(() => {
  const [first, ...rest] = selectedNames.value;
  if (!first) return props.label;
  return rest.length ? `${first} +${rest.length}` : first;
});

const showSearch = computed(() => props.options.length > SEARCH_THRESHOLD);
const visibleOptions = computed(() => {
  const term = search.value.trim().toLowerCase();
  if (!term) return props.options;
  return props.options.filter(option =>
    String(option.name).toLowerCase().includes(term)
  );
});

const isSelected = option => selected.value.includes(option.id);

const toggleOption = option => {
  selected.value = isSelected(option)
    ? selected.value.filter(id => id !== option.id)
    : [...selected.value, option.id];
};

const clear = () => {
  selected.value = [];
};
</script>

<template>
  <DropdownContainer class="min-w-0" @close="search = ''">
    <template #trigger="{ toggle, isOpen }">
      <button
        v-tooltip.top="disabled ? disabledHint : ''"
        type="button"
        class="inline-flex items-center max-w-full h-7 min-w-0 gap-1 px-2 text-xs rounded-full outline outline-1 -outline-offset-1 transition-colors"
        :class="[
          selected.length
            ? 'outline-n-brand bg-n-brand/10 text-n-slate-12'
            : 'outline-n-strong text-n-slate-11',
          disabled ? 'opacity-50 cursor-not-allowed' : 'hover:bg-n-alpha-2',
        ]"
        :disabled="disabled"
        :aria-expanded="isOpen"
        @click="toggle"
      >
        <Icon
          v-if="triggerIcon"
          :icon="triggerIcon"
          class="size-3.5 shrink-0"
        />
        <span class="truncate max-w-32">{{ triggerLabel }}</span>
        <Icon
          v-if="!selected.length"
          icon="i-lucide-chevron-down"
          class="size-3 shrink-0 transition-transform"
          :class="{ 'rotate-180': isOpen }"
        />
        <span
          v-else
          role="button"
          class="flex items-center justify-center rounded-full size-4 shrink-0 hover:bg-n-alpha-3"
          :aria-label="label"
          @click.stop="clear"
        >
          <Icon icon="i-lucide-x" class="size-3" />
        </span>
      </button>
    </template>
    <DropdownBody class="z-50 top-0 min-w-52 max-w-64" strong>
      <li v-if="showSearch" class="px-1 pb-1 list-none">
        <input
          v-model="search"
          type="search"
          :placeholder="searchPlaceholder"
          class="reset-base w-full h-7 px-2 text-xs border rounded-md bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        />
      </li>
      <DropdownSection height="max-h-64">
        <li
          v-if="!visibleOptions.length"
          class="px-2 py-1.5 text-xs text-n-slate-10"
        >
          {{ emptyHint }}
        </li>
        <DropdownItem
          v-for="option in visibleOptions"
          :key="option.id"
          preserve-open
          :click="() => toggleOption(option)"
        >
          <template #icon>
            <span
              class="flex items-center justify-center border rounded size-4 shrink-0"
              :class="
                isSelected(option)
                  ? 'bg-n-brand border-n-brand text-white'
                  : 'border-n-strong'
              "
            >
              <Icon
                v-if="isSelected(option)"
                icon="i-lucide-check"
                class="size-3"
              />
            </span>
          </template>
          <template #label>
            <span class="flex items-center min-w-0 gap-2">
              <span
                v-if="option.color"
                class="rounded-sm size-2 shrink-0"
                :style="{ backgroundColor: option.color }"
              />
              <Icon
                v-else-if="option.icon"
                :icon="option.icon"
                class="size-4 shrink-0 text-n-slate-11"
              />
              <span class="truncate">{{ option.name }}</span>
            </span>
          </template>
        </DropdownItem>
      </DropdownSection>
    </DropdownBody>
  </DropdownContainer>
</template>
