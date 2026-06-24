<script setup>
import { ref, watch, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AudienceGroup from './audience/AudienceGroup.vue';
import { useAudienceFilterTypes } from './audience/useAudienceFilterTypes.js';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();
const { filterTypes } = useAudienceFilterTypes();

let uid = 0;
const nextId = () => {
  uid += 1;
  return `audience-root-${uid}`;
};

const hasConditions = node =>
  node && Object.prototype.hasOwnProperty.call(node, 'conditions');

const defaultRoot = () => ({ id: nextId(), operator: 'and', conditions: [] });

const root = ref(defaultRoot());

const findOption = (filterType, value) =>
  filterType?.options?.find(option => String(option.id) === String(value));

const hydrateValues = (leaf, filterType) => {
  const raw = Array.isArray(leaf.values) ? leaf.values : [leaf.values];
  const inputType = filterType?.inputType;
  if (inputType === 'multiSelect') {
    return raw.map(
      value => findOption(filterType, value) ?? { id: value, name: value }
    );
  }
  if (['searchSelect', 'booleanSelect'].includes(inputType)) {
    return findOption(filterType, raw[0]) ?? { id: raw[0], name: raw[0] };
  }
  return raw[0] ?? '';
};

const hydrateNode = node => {
  if (hasConditions(node)) {
    return {
      id: nextId(),
      operator: node.operator || 'and',
      conditions: (node.conditions || []).map(hydrateNode),
    };
  }

  const filterType = filterTypes.value.find(
    type => type.attributeKey === node.attribute_key
  );
  return {
    id: nextId(),
    attributeKey: node.attribute_key,
    filterOperator: node.filter_operator,
    values: hydrateValues(node, filterType),
    attributeModel: filterType?.attributeModel || 'standard',
  };
};

const hydrateRoot = audience => {
  if (!audience) return defaultRoot();
  const hydrated = hydrateNode(audience);
  return hasConditions(hydrated)
    ? hydrated
    : { id: nextId(), operator: 'and', conditions: [hydrated] };
};

const serializeValues = values => {
  if (Array.isArray(values)) {
    return values[0]?.id ? values.map(value => value.id) : values;
  }
  if (values && typeof values === 'object') {
    return [values.id];
  }
  if (values === '' || values === null || values === undefined) {
    return [];
  }
  return [values];
};

const serializeNode = node => {
  if (hasConditions(node)) {
    return {
      operator: node.operator,
      conditions: node.conditions.map(serializeNode),
    };
  }
  return {
    attribute_key: node.attributeKey,
    filter_operator: node.filterOperator,
    values: serializeValues(node.values),
  };
};

const groupRef = useTemplateRef('groupRef');

const handleSubmit = () => {
  if (!groupRef.value.validate()) return;

  const audience = root.value.conditions.length
    ? serializeNode(root.value)
    : null;

  emit('submit', {
    config: {
      ...props.assistant.config,
      audience,
    },
  });
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) root.value = hydrateRoot(newAssistant.config?.audience);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <AudienceGroup
      ref="groupRef"
      v-model="root"
      is-root
      :filter-types="filterTypes"
    />
    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleSubmit"
      />
    </div>
  </div>
</template>
