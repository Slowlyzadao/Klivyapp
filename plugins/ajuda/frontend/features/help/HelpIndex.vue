<script setup>
import './help.css';
import HelpSearchBar from './components/HelpSearchBar.vue';
import HelpBanner from './components/HelpBanner.vue';
import HelpCategoryGrid from './components/HelpCategoryGrid.vue';
import HelpFaq from './components/HelpFaq.vue';
import HelpArticleDrawer from './components/HelpArticleDrawer.vue';
import { useHelpData } from './composables/useHelpData.js';
import { useChatBubble } from './composables/useChatBubble.js';
import { ref, watch } from 'vue';

const { categories, faqs } = useHelpData();
const { show: showWidget, hide: hideWidget } = useChatBubble();
const drawerData = ref(null);

// Hide widget while drawer is open so it doesn't overlap content
watch(drawerData, val => {
  val ? hideWidget() : showWidget();
});

// ── Article / category actions ─────────────────────────────
function openArticle(cat, art) {
  drawerData.value = { kind: 'article', cat, art };
}

function openCategory(cat) {
  drawerData.value = { kind: 'category', cat };
}

function openChat() {
  const bubble = document.querySelector('.woot-widget-bubble:not(.woot--close):not(.woot--hide)');
  bubble?.click();
}
</script>

<template>
  <div class="help-page">
    <div class="help-page__inner">
      <div class="hp-breadcrumb">
        <a href="#">Início</a>
        <span class="hp-breadcrumb-sep i-lucide-chevron-right" style="font-size: 13px;" />
        <span class="hp-breadcrumb-current">Central de Ajuda</span>
      </div>

      <div class="hp-hero">
        <h1 class="hp-hero__title">Como podemos te ajudar?</h1>
        <p class="hp-hero__sub">Encontre respostas rápidas, tutoriais e contate nosso time quando precisar.</p>
      </div>

      <HelpSearchBar :categories="categories" @open-article="openArticle" />

      <HelpBanner @open-chat="openChat" />

      <HelpCategoryGrid :categories="categories" @open-category="openCategory" />

      <HelpFaq :categories="categories" :faqs="faqs" />

      <footer class="hp-footer">
        <span>© 2026 Klivy · Central de Ajuda</span>
        <div class="hp-footer-links">
          <a href="#">Status do sistema</a>
          <a href="#">Novidades</a>
          <a href="#">Política de privacidade</a>
        </div>
      </footer>
    </div>

    <HelpArticleDrawer
      :data="drawerData"
      @close="drawerData = null"
      @open-article="openArticle"
      @open-chat="openChat"
    />
  </div>
</template>
