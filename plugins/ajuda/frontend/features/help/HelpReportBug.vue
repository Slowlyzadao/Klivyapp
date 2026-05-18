<script setup>
import './help.css';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import HelpFeedbackForm from './components/HelpFeedbackForm.vue';
import { useChatBubble } from './composables/useChatBubble.js';

const router = useRouter();
const { accountScopedRoute } = useAccount();

useChatBubble();

function goToArticles() {
  router.push(accountScopedRoute('ajuda_dashboard_index'));
}
</script>

<template>
  <div class="help-page">
    <div class="help-page__inner">
      <div class="hp-breadcrumb">
        <a href="#" @click.prevent="goToArticles">Início</a>
        <span
          class="hp-breadcrumb-sep i-lucide-chevron-right"
          style="font-size: 13px"
        />
        <a href="#" @click.prevent="goToArticles">Central de Ajuda</a>
        <span
          class="hp-breadcrumb-sep i-lucide-chevron-right"
          style="font-size: 13px"
        />
        <span class="hp-breadcrumb-current">Reportar um erro</span>
      </div>

      <div class="hp-hero">
        <h1 class="hp-hero__title">Encontrou algum problema?</h1>
        <p class="hp-hero__sub">
          Nos conte o que aconteceu para corrigirmos o quanto antes.
        </p>
      </div>

      <HelpFeedbackForm mode="bug" />

      <footer class="hp-footer">
        <span>© 2026 Klivy · Central de Ajuda</span>
        <div class="hp-footer-links">
          <a href="#">Status do sistema</a>
          <a href="#">Novidades</a>
          <a href="#">Política de privacidade</a>
        </div>
      </footer>
    </div>
  </div>
</template>
