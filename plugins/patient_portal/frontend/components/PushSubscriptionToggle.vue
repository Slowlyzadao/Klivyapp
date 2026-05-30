<template>
  <div class="pp-push">
    <div class="pp-push__head">
      <div>
        <h4 class="pp-push__title">Notificações no celular</h4>
        <p class="pp-push__desc">{{ description }}</p>
      </div>
      <span class="pp-push__icon">
        <IconBell :size="22" />
      </span>
    </div>

    <p v-if="error" class="pp-push__error">{{ error }}</p>

    <button
      type="button"
      class="pp-push__btn"
      :class="{ 'pp-push__btn--off': push.subscribed }"
      :disabled="push.busy || !push.supported"
      @click="toggle"
    >
      <span v-if="push.busy">Aguarde…</span>
      <span v-else-if="!push.supported">Indisponível neste dispositivo</span>
      <span v-else-if="push.subscribed">Desativar notificações</span>
      <span v-else>Ativar notificações</span>
    </button>
  </div>
</template>

<script setup>
// Componente isolado e reusável (Sprint G).
//
// Toda a lógica de detect/subscribe/unsubscribe mora na store `push.js` —
// aqui só renderizamos estado e disparamos actions. Mantém o componente
// fácil de testar e mover pra outra página se necessário.
import { computed, onMounted, ref } from 'vue';
import { usePushStore } from '../store/push';
import IconBell from './icons/IconBell.vue';

const push = usePushStore();
const error = ref(null);

onMounted(() => push.hydrate());

const description = computed(() => {
  if (!push.supported)        return 'Seu navegador ou dispositivo não suporta push. Em iPhone, instale o app na tela inicial para habilitar.';
  if (push.permission === 'denied') return 'Permissão negada. Habilite nas configurações do navegador.';
  if (push.subscribed)         return 'Você receberá avisos de pagamento confirmado, novas mensagens e lembretes de consulta.';
  return 'Receba avisos importantes mesmo com o app fechado.';
});

async function toggle() {
  error.value = null;
  const ok = push.subscribed ? await push.unsubscribe() : await push.subscribe();
  if (!ok) error.value = push.error;
}
</script>

<style scoped>
.pp-push {
  margin: 0 28px 24px; padding: 16px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 16px;
}
.pp-push__head { display: flex; align-items: center; gap: 12px; justify-content: flex-end; flex-direction: row-reverse;}
.pp-push__title { margin: 0; font-size: 15px; font-weight: 700; color: var(--pp-color-text); }
.pp-push__desc  { margin: 4px 0 0; font-size: 12px; color: var(--pp-color-text-muted); line-height: 1.4; }
.pp-push__icon  { width: 36px; height: 36px; border-radius: 10px; display: flex; align-items: center; justify-content: center; background: #06b6d41a; color: #06b6d4; flex: none; }
.pp-push__error { margin: 10px 0 0; font-size: 12px; color: #b91c1c; }
.pp-push__btn {
  margin-top: 12px; width: 100%; padding: 12px;
  background: var(--pp-color-primary); color: #fff;
  border: 0; border-radius: 12px; font-size: 14px; font-weight: 600; cursor: pointer;
  transition: opacity 120ms ease;
}
.pp-push__btn:disabled { opacity: 0.5; cursor: not-allowed; }
.pp-push__btn--off { background: #fff; color: #b91c1c; border: 1px solid #fecaca; }
</style>
