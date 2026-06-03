<script setup>
import CopilotThinkingGroup from './CopilotThinkingGroup.vue';

const messages = [
  {
    id: 1,
    message: {
      content: 'Analyzing the user query',
      reasoning: 'Breaking down the request into actionable steps',
    },
  },
  {
    id: 2,
    message: {
      content: 'Searching codebase',
      reasoning: 'Looking for relevant files and functions',
    },
  },
  {
    id: 3,
    message: {
      content: 'Generating response',
      reasoning: 'Composing a helpful and accurate answer',
    },
  },
];
</script>

<template>
  <Story title="Captain/Copilot/CopilotThinkingGroup" group="components">
    <Variant title="Default">
      <CopilotThinkingGroup :messages="messages" />
    </Variant>

    <Variant title="With Default Collapsed">
      <!-- eslint-disable-next-line -->
      <CopilotThinkingGroup :messages="messages" :default-collapsed="true" />
    </Variant>
  </Story>
</template>
