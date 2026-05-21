<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversations: { type: Array, default: () => [] },
  contacts: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  startingContactId: { type: [Number, String], default: null },
  // Quando a query parece ser um número e nenhum contato/conversa bate,
  // mostramos o CTA WhatsApp Web. Os textos vêm do pai (ChatList) que já
  // tem a lógica de normalização de phone — evita duplicar regex aqui.
  phoneCandidate: { type: String, default: '' },
  phoneCandidateLabel: { type: String, default: '' },
  startingNewConversation: { type: Boolean, default: false },
});

const emit = defineEmits([
  'selectConversation',
  'startConversation',
  'startConversationByPhone',
]);

const hasResults = computed(
  () => props.conversations.length > 0 || props.contacts.length > 0
);

const onSelectConversation = conversation => {
  emit('selectConversation', conversation);
};

const onStartConversation = contact => {
  if (!contact.phone_number) return;
  emit('startConversation', contact);
};

const onStartByPhone = () => emit('startConversationByPhone');
</script>

<template>
  <div class="flex flex-col gap-4 p-3 overflow-y-auto bcl-search-results">
    <div
      v-if="loading"
      class="flex justify-center items-center py-6 text-n-slate-11"
    >
      <Spinner class="text-n-brand" />
    </div>

    <template v-else>
      <!-- Conversas existentes -->
      <section v-if="conversations.length" class="flex flex-col gap-1">
        <h3
          class="px-1 text-xs font-medium tracking-wide uppercase text-n-slate-10"
        >
          Conversas
        </h3>
        <button
          v-for="conv in conversations"
          :key="`conv-${conv.id}`"
          type="button"
          class="flex gap-3 items-center px-2 py-2 rounded-md transition-colors hover:bg-n-slate-3 text-left"
          @click="onSelectConversation(conv)"
        >
          <Avatar
            :name="conv.contact?.name || '?'"
            :src="conv.contact?.thumbnail"
            :size="32"
          />
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ conv.contact?.name || conv.contact?.phone_number || '—' }}
            </span>
            <span
              v-if="conv.last_message?.content"
              class="text-xs truncate text-n-slate-11"
            >
              {{ conv.last_message.content }}
            </span>
            <span
              v-else-if="conv.contact?.phone_number"
              class="text-xs truncate text-n-slate-11"
            >
              {{ conv.contact.phone_number }}
            </span>
          </div>
        </button>
      </section>

      <!-- Contatos sem conversa -->
      <section v-if="contacts.length" class="flex flex-col gap-1">
        <h3
          class="px-1 text-xs font-medium tracking-wide uppercase text-n-slate-10"
        >
          Contatos
        </h3>
        <div
          v-for="contact in contacts"
          :key="`contact-${contact.id}`"
          class="flex gap-3 items-center px-2 py-2 rounded-md hover:bg-n-slate-3"
        >
          <Avatar
            :name="contact.name || '?'"
            :src="contact.thumbnail"
            :size="32"
          />
          <div class="flex flex-col flex-1 min-w-0">
            <span class="text-sm font-medium truncate text-n-slate-12">
              {{ contact.name || contact.phone_number || '—' }}
            </span>
            <span
              v-if="contact.phone_number"
              class="text-xs truncate text-n-slate-11"
            >
              {{ contact.phone_number }}
            </span>
            <span v-else class="text-xs italic text-n-slate-10">
              sem telefone
            </span>
          </div>
          <button
            type="button"
            :disabled="!contact.phone_number || startingContactId === contact.id"
            class="px-3 py-1 text-xs font-medium rounded-md bg-n-brand text-n-slate-1 hover:bg-n-brand/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed shrink-0"
            @click="onStartConversation(contact)"
          >
            <span v-if="startingContactId === contact.id" class="flex items-center gap-1">
              <span class="i-lucide-loader-2 animate-spin size-3" />
              Iniciando…
            </span>
            <span v-else>Iniciar conversa</span>
          </button>
        </div>
      </section>

      <!-- Empty + CTA telefônico (estilo WhatsApp Web) -->
      <div
        v-if="!hasResults"
        class="flex flex-col gap-3 justify-center items-center px-4 py-6 text-center"
      >
        <p class="m-0 text-sm text-n-slate-11">
          Nenhuma conversa ou contato encontrado.
        </p>
        <button
          v-if="phoneCandidate"
          type="button"
          :disabled="startingNewConversation"
          class="flex gap-2 items-center px-4 py-2 text-sm font-medium rounded-lg bg-n-brand text-n-slate-1 hover:bg-n-brand/90 transition-colors disabled:opacity-60 disabled:cursor-wait"
          @click="onStartByPhone"
        >
          <span
            :class="
              startingNewConversation
                ? 'i-lucide-loader-2 animate-spin size-4'
                : 'i-woot-whatsapp size-4'
            "
          />
          {{
            startingNewConversation
              ? 'Validando número...'
              : `Iniciar conversa com ${phoneCandidateLabel}`
          }}
        </button>
      </div>
    </template>
  </div>
</template>
