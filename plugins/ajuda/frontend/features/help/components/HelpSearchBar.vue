<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue';

const props = defineProps({
  categories: { type: Array, required: true },
});

const emit = defineEmits(['openArticle']);

const query     = ref('');
const focused   = ref(false);
const activeCat = ref(null);
const wrapEl    = ref(null);
const pillsEl   = ref(null);

// ── Computed ───────────────────────────────────────────────
const displayCats = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) return props.categories;
  return props.categories.filter(cat => {
    if (cat.name.toLowerCase().includes(q)) return true;
    return (cat.articles ?? []).some(art => {
      const body = (art.body ?? '').replace(/<[^>]*>/g, ' ').toLowerCase();
      return art.title.toLowerCase().includes(q) || body.includes(q);
    });
  });
});

const matches = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) return [];
  const out = [];
  props.categories.forEach(cat => {
    (cat.articles ?? []).forEach(art => {
      const bodyText = (art.body ?? '').replace(/<[^>]*>/g, ' ').toLowerCase();
      if (art.title.toLowerCase().includes(q) || cat.name.toLowerCase().includes(q) || bodyText.includes(q)) {
        out.push({ cat, art });
      }
    });
  });
  return out.slice(0, 8);
});

const catArticles = computed(() => activeCat.value?.articles ?? []);

// Clear active category when user starts typing
watch(query, v => { if (v.trim()) activeCat.value = null; });

// ── Pill selection + centering ─────────────────────────────
function selectPill(cat) {
  // Toggle off if clicking the same pill
  if (activeCat.value?.id === cat.id) {
    activeCat.value = null;
    return;
  }
  activeCat.value = cat;
  scrollPillToCenter(cat.id);
}

async function scrollPillToCenter(catId) {
  await nextTick();
  const container = pillsEl.value;
  if (!container) return;
  const btn = container.querySelector(`[data-cat-id="${catId}"]`);
  if (!btn) return;
  const targetLeft = btn.offsetLeft - container.offsetWidth / 2 + btn.offsetWidth / 2;
  container.scrollTo({ left: targetLeft, behavior: 'smooth' });
}

// ── Drag-to-scroll pills ───────────────────────────────────
const drag = { el: null, active: false, startX: 0, scrollLeft: 0, moved: false };

function onPillsDragStart(e) {
  drag.el = e.currentTarget;
  drag.active = true;
  drag.moved = false;
  drag.startX = e.pageX;
  drag.scrollLeft = drag.el.scrollLeft;
  drag.el.style.cursor = 'grabbing';
}

function onPillsDragMove(e) {
  if (!drag.active) return;
  const delta = e.pageX - drag.startX;
  if (Math.abs(delta) > 4) {
    drag.moved = true;
    e.preventDefault();
    drag.el.scrollLeft = drag.scrollLeft - delta;
  }
}

function onPillsDragEnd() {
  if (drag.el) drag.el.style.cursor = '';
  drag.active = false;
  drag.el = null;
}

// ── Helpers ────────────────────────────────────────────────
function highlightMatch(text) {
  const q = query.value.trim();
  if (!q) return text;
  const idx = text.toLowerCase().indexOf(q.toLowerCase());
  if (idx === -1) return text;
  return (
    text.slice(0, idx) +
    '<mark>' +
    text.slice(idx, idx + q.length) +
    '</mark>' +
    text.slice(idx + q.length)
  );
}

function select(cat, art) {
  emit('openArticle', cat, art);
  query.value     = '';
  focused.value   = false;
  activeCat.value = null;
}

function onClickOutside(e) {
  if (wrapEl.value && !wrapEl.value.contains(e.target)) {
    focused.value   = false;
    activeCat.value = null;
  }
}

function onKeydown(e) {
  if (e.key === 'Escape') {
    if (activeCat.value) { activeCat.value = null; return; }
    focused.value = false;
  }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
    e.preventDefault();
    wrapEl.value?.querySelector('input')?.focus();
  }
}

onMounted(() => {
  document.addEventListener('mousedown', onClickOutside);
  window.addEventListener('keydown', onKeydown);
});
onUnmounted(() => {
  document.removeEventListener('mousedown', onClickOutside);
  window.removeEventListener('keydown', onKeydown);
});
</script>

<template>
  <div ref="wrapEl" class="hp-search-wrap">
    <div class="hp-search-box">
      <span class="hp-search-icon i-lucide-search" />
      <input
        v-model="query"
        type="text"
        placeholder="Busque por um tópico, artigo ou palavra-chave..."
        @focus="focused = true"
      />
      <div class="hp-search-kbd">
        <span class="hp-kbd">⌘</span>
        <span class="hp-kbd">K</span>
      </div>
    </div>

    <Transition name="hp-fade">
      <div v-if="focused" class="hp-results">

        <!-- Pills row — always visible when dropdown is open -->
        <div class="hp-results-label">Explorar por categoria</div>
        <div
          ref="pillsEl"
          class="hp-browse-pills"
          @mousedown="onPillsDragStart"
          @mousemove="onPillsDragMove"
          @mouseup="onPillsDragEnd"
          @mouseleave="onPillsDragEnd"
        >
          <button
            v-for="cat in displayCats"
            :key="cat.id"
            :data-cat-id="cat.id"
            :class="['hp-browse-pill', activeCat?.id === cat.id && 'hp-browse-pill--active']"
            @click.stop="selectPill(cat)"
          >
            <!-- eslint-disable-next-line vue/no-v-html -->
            <span v-if="cat.iconSvg" class="hp-browse-pill-svg" v-html="cat.iconSvg" />
            <span v-else :class="cat.icon" style="font-size: 13px;" />
            {{ cat.name }}
          </button>
        </div>

        <!-- Content below pills: search results or category articles -->
        <template v-if="query.trim()">
          <div v-if="matches.length === 0" class="hp-results-empty">
            Nenhum resultado para <strong>"{{ query }}"</strong>. Tente outra palavra.
          </div>
          <div v-else class="hp-results-group">
            <div class="hp-results-label">{{ matches.length }} resultado{{ matches.length > 1 ? 's' : '' }}</div>
            <button
              v-for="{ cat, art } in matches"
              :key="art.id"
              class="hp-result-btn"
              @click="select(cat, art)"
            >
              <div class="hp-result-icon"><span class="i-lucide-file-text" /></div>
              <div style="flex: 1; min-width: 0;">
                <!-- eslint-disable-next-line vue/no-v-html -->
                <div class="hp-result-title" v-html="highlightMatch(art.title)" />
                <div class="hp-result-meta">{{ cat.name }} · {{ art.time || 'Leitura rápida' }}</div>
              </div>
              <span class="hp-result-chev i-lucide-chevron-right" />
            </button>
          </div>
        </template>

        <template v-else-if="activeCat">
          <div class="hp-results-label hp-results-label--nav">
            <span>{{ activeCat.name }}</span>
            <span class="hp-label-meta">· {{ catArticles.length }} artigo{{ catArticles.length !== 1 ? 's' : '' }}</span>
          </div>
          <div class="hp-cat-art-list">
            <div v-if="catArticles.length === 0" class="hp-results-empty">
              Nenhum artigo nesta categoria ainda.
            </div>
            <button
              v-for="art in catArticles"
              :key="art.id"
              class="hp-result-btn"
              @click="select(activeCat, art)"
            >
              <div class="hp-result-icon"><span class="i-lucide-file-text" /></div>
              <div style="flex: 1; min-width: 0;">
                <div class="hp-result-title">{{ art.title }}</div>
                <div class="hp-result-meta">{{ art.time || 'Leitura rápida' }}</div>
              </div>
              <span class="hp-result-chev i-lucide-chevron-right" />
            </button>
          </div>
        </template>

      </div>
    </Transition>
  </div>
</template>
