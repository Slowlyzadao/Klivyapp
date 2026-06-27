<script setup>
import { ref, computed, onMounted, nextTick, watch } from 'vue';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import UrgentTriageModal from '../components/UrgentTriageModal.vue';
import IconMessage from '../components/icons/IconMessage.vue';
import { useMessagesStore } from '../store/messages';
import { formatTime } from '../utils/format';

const messages = useMessagesStore();

const draft = ref('');
const listRef = ref(null);
const showTriage = ref(false);
const triageKeywords = ref([]);
const triagePhone = ref(null);

const canSend = computed(
  () => draft.value.trim().length > 0 && !messages.sending
);

function bubbleClass(m, i) {
  return [
    m.sent_by_me ? 'pp-msgs__item--mine' : 'pp-msgs__item--theirs',
    i > 0 && messages.messages[i - 1].sent_by_me === m.sent_by_me
      ? 'pp-msgs__item--continued'
      : '',
  ];
}

async function scrollToBottom() {
  await nextTick();
  const el = listRef.value;
  if (el) el.scrollTop = el.scrollHeight;
}

async function onSubmit() {
  const text = draft.value.trim();
  if (!text) return;

  // Consultativo: pergunta ao backend se é urgente — se sim, mostra modal
  const triage = await messages.triage(text);
  if (triage.urgent) {
    triageKeywords.value = triage.keywords || [];
    triagePhone.value = triage.clinic_phone;
    showTriage.value = true;
    return;
  }

  await doSend(text);
}

async function doSend(text) {
  try {
    await messages.send(text);
    draft.value = '';
    await scrollToBottom();
  } catch (_) {
    /* erro fica em messages.error */
  }
}

function onTriageCancel() {
  showTriage.value = false;
}
async function onTriageSendAnyway() {
  showTriage.value = false;
  await doSend(draft.value.trim());
}

onMounted(async () => {
  await messages.fetch();
  await scrollToBottom();
});

watch(
  () => messages.messages.length,
  () => scrollToBottom()
);
</script>

<template>
  <AppShell>
    <PageHeader title="Conversa com a clínica" back @back="$router.back()" />

    <div
      class="pp-msgs"
      :class="{
        'pp-msgs--empty': !messages.loading && messages.messages.length === 0,
      }"
    >
      <div v-if="messages.loading" class="pp-msgs__loading">Carregando…</div>

      <ul
        v-else-if="messages.messages.length > 0"
        ref="listRef"
        class="pp-msgs__list"
      >
        <li
          v-for="(m, i) in messages.messages"
          :key="m.id"
          class="pp-msgs__item"
          :class="bubbleClass(m, i)"
        >
          <div
            class="pp-msgs__bubble"
            :class="{ 'pp-msgs__bubble--urgent': m.urgent }"
          >
            <div class="pp-msgs__content">{{ m.content }}</div>
            <div class="pp-msgs__meta">
              <span class="pp-msgs__sender">{{ m.sender_name }}</span>
              <span class="pp-msgs__sep">·</span>
              <span class="pp-msgs__time">{{ formatTime(m.created_at) }}</span>
              <span
v-if="m.urgent" class="pp-msgs__urgent-tag"
                >⚠ marcada urgente</span
              >
            </div>
          </div>
        </li>
      </ul>

      <div v-else class="pp-msgs__empty">
        <IconMessage :size="48" />
        <h3>Nenhuma mensagem ainda</h3>
        <p>
          Use este canal para tirar dúvidas com a recepção. Resposta em horário
          comercial.
        </p>
      </div>
    </div>

    <!-- Composer fixo no rodapé -->
    <form class="pp-msgs__composer" @submit.prevent="onSubmit">
      <textarea
        v-model="draft"
        :disabled="messages.sending"
        placeholder="Escreva sua mensagem…"
        rows="2"
        maxlength="4000"
        class="pp-msgs__input"
      />
      <button type="submit" class="pp-msgs__send" :disabled="!canSend">
        <span v-if="messages.sending">…</span>
        <span v-else>Enviar</span>
      </button>
    </form>

    <p v-if="messages.error" class="pp-msgs__error">{{ messages.error }}</p>

    <UrgentTriageModal
      :open="showTriage"
      :keywords="triageKeywords"
      :phone="triagePhone"
      @cancel="onTriageCancel"
      @send-anyway="onTriageSendAnyway"
    />
  </AppShell>
</template>

<style scoped>
.pp-msgs {
  padding: 8px var(--pp-content-pad-x) 80px; /* espaço pro composer fixo */
  display: flex;
  flex-direction: column;
  min-height: calc(100vh - 200px);
}
.pp-msgs--empty {
  justify-content: center;
  align-items: center;
}
.pp-msgs__loading {
  padding: 32px;
  text-align: center;
  color: var(--pp-color-text-muted);
  font-size: 14px;
}

.pp-msgs__list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.pp-msgs__item {
  display: flex;
}
.pp-msgs__item--mine {
  justify-content: flex-end;
}
.pp-msgs__item--theirs {
  justify-content: flex-start;
}
.pp-msgs__item--continued {
  margin-top: -2px;
}
.pp-msgs__item--continued .pp-msgs__meta {
  display: none;
}

.pp-msgs__bubble {
  max-width: 75%;
  padding: 10px 14px;
  border-radius: 16px;
  font-size: 14px;
  line-height: 1.4;
  word-wrap: break-word;
}
.pp-msgs__item--mine .pp-msgs__bubble {
  background: var(--pp-color-primary);
  color: #fff;
  border-bottom-right-radius: 6px;
}
.pp-msgs__item--theirs .pp-msgs__bubble {
  background: #f1f5f9;
  color: var(--pp-color-text);
  border-bottom-left-radius: 6px;
}
.pp-msgs__bubble--urgent {
  outline: 2px solid #fbbf24;
  outline-offset: 2px;
}

.pp-msgs__content {
  white-space: pre-wrap;
}
.pp-msgs__meta {
  margin-top: 4px;
  font-size: 11px;
  opacity: 0.8;
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}
.pp-msgs__urgent-tag {
  color: #b45309;
  font-weight: 700;
}
.pp-msgs__item--mine .pp-msgs__urgent-tag {
  color: #fde68a;
}

.pp-msgs__empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 48px 24px;
  text-align: center;
  color: var(--pp-color-text-muted);
}
.pp-msgs__empty :first-child {
  color: var(--pp-color-primary);
  opacity: 0.4;
}
.pp-msgs__empty h3 {
  margin: 0;
  font-size: 16px;
  font-weight: 700;
  color: var(--pp-color-text);
}
.pp-msgs__empty p {
  margin: 0;
  font-size: 13px;
}

.pp-msgs__composer {
  position: fixed;
  bottom: 56px; /* acima do bottom-nav (mobile/tablet) */
  left: 0;
  right: 0;
  max-width: 720px;
  margin: 0 auto;
  padding: 10px var(--pp-content-pad-x);
  background: #fff;
  border-top: 1px solid var(--pp-color-border);
  display: flex;
  gap: 8px;
  align-items: flex-end;
  z-index: 10;
}
@media (min-width: 1024px) {
  /* Desktop: sidebar à esquerda, sem bottom-nav → composer cola na base do main */
  .pp-msgs__composer {
    bottom: 0;
    left: var(--pp-sidenav-width);
    right: 0;
    max-width: var(--pp-content-max);
    margin: 0 auto;
  }
}
.pp-msgs__input {
  flex: 1;
  padding: 10px 12px;
  border-radius: 14px;
  border: 1px solid var(--pp-color-border);
  font-size: 14px;
  font-family: inherit;
  resize: none;
  line-height: 1.4;
}
.pp-msgs__send {
  background: var(--pp-color-primary);
  color: #fff;
  border: none;
  padding: 10px 16px;
  border-radius: 12px;
  font-size: 14px;
  font-weight: 700;
  cursor: pointer;
  white-space: nowrap;
}
.pp-msgs__send:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}
.pp-msgs__error {
  color: #b91c1c;
  font-size: 13px;
  text-align: center;
  margin: 0 0 12px;
  padding: 0 16px;
}
</style>
