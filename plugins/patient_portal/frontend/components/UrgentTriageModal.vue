<template>
  <transition name="pp-modal-fade">
    <div v-if="open" class="pp-urg-modal" role="dialog" aria-modal="true">
      <div class="pp-urg-modal__backdrop" @click="$emit('cancel')" />
      <div class="pp-urg-modal__panel">
        <div class="pp-urg-modal__icon"><IconInfo :size="24" /></div>
        <h3 class="pp-urg-modal__title">Isso parece uma urgência</h3>
        <p class="pp-urg-modal__body">
          Identificamos termos como
          <strong>{{ keywords.join(', ') }}</strong>
          na sua mensagem. <strong>Mensagens no portal não são monitoradas em tempo real.</strong>
          Se for emergência, ligue para a clínica agora.
        </p>

        <div class="pp-urg-modal__actions">
          <a v-if="phone" :href="`tel:${phone}`" class="pp-urg-modal__cta-call">
            📞 Ligar agora
          </a>
          <button v-else type="button" class="pp-urg-modal__cta-call" disabled>
            Telefone não cadastrado
          </button>

          <button type="button" class="pp-urg-modal__cta-send" @click="$emit('send-anyway')">
            Enviar mensagem mesmo assim
          </button>
          <button type="button" class="pp-urg-modal__cta-cancel" @click="$emit('cancel')">
            Voltar e editar
          </button>
        </div>
      </div>
    </div>
  </transition>
</template>

<script setup>
import IconInfo from './icons/IconInfo.vue';

defineProps({
  open:     { type: Boolean, default: false },
  keywords: { type: Array,   default: () => [] },
  phone:    { type: String,  default: null }
});
defineEmits(['cancel', 'send-anyway']);
</script>

<style scoped>
.pp-urg-modal {
  position: fixed; inset: 0; z-index: 1000;
  display: flex; align-items: flex-end; justify-content: center;
}
.pp-urg-modal__backdrop { position: absolute; inset: 0; background: rgba(15,23,42,.5); backdrop-filter: blur(2px); }
.pp-urg-modal__panel {
  position: relative; width: 100%; max-width: 460px;
  background: #fff; border-radius: 20px 20px 0 0;
  padding: 24px 20px 32px; box-shadow: 0 -8px 24px rgba(0,0,0,.15);
}
.pp-urg-modal__icon {
  width: 48px; height: 48px; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  background: #fee2e2; color: #b91c1c;
  margin-bottom: 12px;
}
.pp-urg-modal__title { margin: 0 0 8px; font-size: 18px; font-weight: 700; color: var(--pp-color-text); }
.pp-urg-modal__body  { margin: 0 0 20px; font-size: 14px; line-height: 1.5; color: var(--pp-color-text-muted); }
.pp-urg-modal__body strong { color: var(--pp-color-text); }

.pp-urg-modal__actions { display: flex; flex-direction: column; gap: 8px; }
.pp-urg-modal__cta-call {
  background: #dc2626; color: #fff; padding: 14px; border-radius: 12px;
  font-size: 15px; font-weight: 700; text-decoration: none;
  text-align: center; border: none; cursor: pointer;
}
.pp-urg-modal__cta-call:disabled { opacity: .6; cursor: not-allowed; }
.pp-urg-modal__cta-send {
  background: transparent; color: var(--pp-color-text-muted); padding: 12px;
  border: 1px solid var(--pp-color-border); border-radius: 12px;
  font-size: 14px; font-weight: 600; cursor: pointer;
}
.pp-urg-modal__cta-cancel {
  background: transparent; color: var(--pp-color-text-muted); padding: 8px;
  border: none; font-size: 13px; font-weight: 600; cursor: pointer;
}

.pp-modal-fade-enter-active, .pp-modal-fade-leave-active { transition: opacity 150ms ease; }
.pp-modal-fade-enter-from, .pp-modal-fade-leave-to     { opacity: 0; }
.pp-modal-fade-enter-active .pp-urg-modal__panel,
.pp-modal-fade-leave-active .pp-urg-modal__panel { transition: transform 180ms ease; }
.pp-modal-fade-enter-from .pp-urg-modal__panel { transform: translateY(20px); }
.pp-modal-fade-leave-to   .pp-urg-modal__panel { transform: translateY(20px); }
</style>
