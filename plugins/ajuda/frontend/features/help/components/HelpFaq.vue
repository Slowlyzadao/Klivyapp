<script setup>
import { ref, computed, nextTick } from 'vue';

const props = defineProps({
  categories: { type: Array, required: true },
  faqs:       { type: Array, required: true },
});

const activeCat = ref('todos');
const openId    = ref(null);
const pillsEl   = ref(null);

// All categories, same as search bar — never filter by hidden here
const faqCats = computed(() => props.categories);

const filtered = computed(() => {
  if (activeCat.value === 'todos') return props.faqs;
  return props.faqs.filter(f => f.cat === activeCat.value);
});

function toggle(id) {
  openId.value = openId.value === id ? null : id;
}

async function selectCat(id) {
  activeCat.value = id;
  await scrollPillToCenter(id);
}

async function scrollPillToCenter(catId) {
  await nextTick();
  const container = pillsEl.value;
  if (!container) return;
  const btn = container.querySelector(`[data-chip-id="${catId}"]`);
  if (!btn) return;
  const targetLeft = btn.offsetLeft - container.offsetWidth / 2 + btn.offsetWidth / 2;
  container.scrollTo({ left: targetLeft, behavior: 'smooth' });
}

// ── Drag-to-scroll ─────────────────────────────────────────
const drag = { el: null, active: false, startX: 0, scrollLeft: 0, moved: false };

function onDragStart(e) {
  drag.el = e.currentTarget;
  drag.active = true;
  drag.moved = false;
  drag.startX = e.pageX;
  drag.scrollLeft = drag.el.scrollLeft;
  drag.el.style.cursor = 'grabbing';
}
function onDragMove(e) {
  if (!drag.active) return;
  const delta = e.pageX - drag.startX;
  if (Math.abs(delta) > 4) {
    drag.moved = true;
    e.preventDefault();
    drag.el.scrollLeft = drag.scrollLeft - delta;
  }
}
function onDragEnd() {
  if (drag.el) drag.el.style.cursor = '';
  drag.active = false;
  drag.el = null;
}
</script>

<template>
  <section class="hp-faq-section">
    <div class="hp-section-head">
      <span class="hp-section-title">Perguntas frequentes</span>
      <span class="hp-section-meta">Respostas rápidas para as dúvidas mais comuns</span>
    </div>

    <div
      ref="pillsEl"
      class="hp-faq-filter"
      @mousedown="onDragStart"
      @mousemove="onDragMove"
      @mouseup="onDragEnd"
      @mouseleave="onDragEnd"
    >
      <button
        data-chip-id="todos"
        :class="['hp-chip', activeCat === 'todos' && 'hp-chip--active']"
        @click.stop="selectCat('todos')"
      >
        Todas
      </button>
      <button
        v-for="cat in faqCats"
        :key="cat.id"
        :data-chip-id="cat.id"
        :class="['hp-chip', activeCat === cat.id && 'hp-chip--active']"
        @click.stop="selectCat(cat.id)"
      >
        {{ cat.name }}
      </button>
    </div>

    <div class="hp-faq-list">
      <template v-if="filtered.length > 0">
        <div
          v-for="item in filtered"
          :key="item.id"
          :class="['hp-faq-item', openId === item.id && 'hp-faq-item--open']"
        >
          <button class="hp-faq-q" @click="toggle(item.id)">
            <span>{{ item.question }}</span>
            <span class="hp-faq-chev i-lucide-chevron-down" />
          </button>
          <div class="hp-faq-a">
            <div class="hp-faq-a-inner">
              <div class="hp-faq-a-content">
                {{ item.answer }}
                <div v-if="item.tags && item.tags.length" class="hp-faq-tags">
                  <span v-for="tag in item.tags" :key="tag" class="hp-tag">#{{ tag }}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </template>
      <div v-else class="hp-faq-empty">
        Sem perguntas nessa categoria — explore os artigos acima.
      </div>
    </div>
  </section>
</template>
