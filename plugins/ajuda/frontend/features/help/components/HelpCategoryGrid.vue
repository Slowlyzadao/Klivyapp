<script setup>
import { computed } from 'vue';

const props = defineProps({
  categories: { type: Array, required: true },
});

const emit = defineEmits(['openCategory']);

const visibleCategories = computed(() =>
  props.categories.filter(c => !c.hidden)
);

const totalArticles = computed(() =>
  props.categories.reduce((sum, c) => sum + (c.articles?.length ?? c.count ?? 0), 0)
);
</script>

<template>
  <section class="hp-cat-section">
    <div class="hp-section-head">
      <span class="hp-section-title">Explorar por categoria</span>
      <span class="hp-section-meta">{{ totalArticles }} artigos no total</span>
    </div>
    <div class="hp-cat-grid">
      <button
        v-for="cat in visibleCategories"
        :key="cat.id"
        class="hp-cat-card"
        @click="emit('openCategory', cat)"
      >
        <div class="hp-cat-icon">
          <!-- eslint-disable-next-line vue/no-v-html -->
          <span v-if="cat.iconSvg" class="hp-cat-svg-icon" v-html="cat.iconSvg" />
          <span v-else :class="cat.icon" />
        </div>
        <div class="hp-cat-name">
          <span>{{ cat.name }}</span>
          <span class="hp-cat-arrow i-lucide-arrow-right" />
        </div>
        <div class="hp-cat-desc">{{ cat.description }}</div>
        <div class="hp-cat-foot">
          <span class="i-lucide-file-text" style="font-size: 12px;" />
          {{ cat.articles?.length ?? cat.count ?? 0 }} artigos
        </div>
      </button>
    </div>
  </section>
</template>
