<script setup>
import { ref } from 'vue';
import Copilot from './Copilot.vue';

const messages = ref([
  {
    id: 1,
    message_type: 'user',
    message: { content: 'Hi there! How can I help you today?' },
  },
  {
    id: 2,
    message_type: 'assistant_thinking',
    message: {
      content: 'Analyzing the conversation',
      reasoning: 'Breaking down the request into actionable steps',
    },
  },
  {
    id: 3,
    message_type: 'assistant_thinking',
    message: {
      content: 'Searching the knowledge base',
      reasoning: 'Looking for relevant articles and past replies',
    },
  },
  {
    id: 4,
    message_type: 'assistant',
    message: {
      content:
        "Hello! I'm the AI assistant. I'll be helping the support team today.",
    },
  },
]);

const sendMessage = message => {
  messages.value.push({
    id: messages.value.length + 1,
    message_type: 'user',
    message: { content: message },
  });

  // Simulate AI response
  setTimeout(() => {
    messages.value.push({
      id: messages.value.length + 1,
      message_type: 'assistant',
      message: { content: 'This is a simulated AI response.' },
    });
  }, 2000);
};
</script>

<template>
  <Story
    title="Captain/Copilot"
    :layout="{ type: 'grid', width: '400px', height: '800px' }"
  >
    <Copilot
      :messages="messages"
      conversation-inbox-type="Channel::WebWidget"
      @send-message="sendMessage"
    />
  </Story>
</template>
