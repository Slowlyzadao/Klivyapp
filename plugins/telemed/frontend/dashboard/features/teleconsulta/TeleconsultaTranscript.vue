<script setup>
// Transcrição da teleconsulta no formato de chat (DR/PACIENTE).
// Audit Fase 3 — virtualizada via `DynamicScroller` (vue-virtual-scroller).
// Antes mostrava só PAGE_SIZE iniciais e tinha botão "Carregar mais";
// consulta de 1h+ tem 200-800 segmentos → loop crescente de DOM nodes
// degradava scroll em low-end. Agora rendera só o viewport (~10 nodes)
// independente da contagem total.
//
// `DynamicScroller` (vs `RecycleScroller`) acomoda alturas variáveis
// (mensagens curtas/longas) sem precisar declarar `item-size` fixo.
//
// 2026-05-25 — Modo karaokê: destaca o segmento sendo falado no player.
// Pai (DetailPage) escuta `time-update` do player e passa `currentTime`
// como prop. Encontramos o segmento ativo via busca binária (O(log N) por
// tick @ ~4 Hz; insignificante mesmo com 1000+ segments). Auto-scroll
// inteligente: só rola se o usuário não interagiu com a transcrição nos
// últimos 4s, pra não roubar scroll quando ele está lendo manualmente.
import { computed, ref, watch, onBeforeUnmount, onMounted } from 'vue';
import { DynamicScroller, DynamicScrollerItem } from 'vue-virtual-scroller';
import 'vue-virtual-scroller/dist/vue-virtual-scroller.css';
import { initialsFromName, formatClockSeconds } from './utils/formatters.js';

const props = defineProps({
  segments: { type: Array, default: () => [] },
  text: { type: String, default: '' },
  doctorName: { type: String, default: 'Dr.' },
  patientName: { type: String, default: 'Paciente' },
  // Tempo atual do player (segundos). 0 = parado/sem áudio. Quando muda
  // (~4 Hz), recomputamos `activeIndex` e potencialmente auto-scrollamos.
  currentTime: { type: Number, default: 0 },
});
const emit = defineEmits(['segment-click']);

const scrollerRef = ref(null);
// Timestamp da última interação manual do usuário com a transcrição (scroll
// roda do mouse ou clique em segment). Auto-scroll só dispara se passou
// USER_INTERACTION_GRACE_MS desde essa interação — evita roubar o scroll
// enquanto o usuário tá lendo outro trecho. 4s cobre o caso "li, soltei o
// mouse, espero o áudio alcançar" sem irritar.
const userInteractedAt = ref(0);
const USER_INTERACTION_GRACE_MS = 4000;
const markUserInteraction = () => { userInteractedAt.value = Date.now(); };

const hasSegments = computed(() =>
  Array.isArray(props.segments) && props.segments.length > 0
);

// 2026-05-25 — Agrupamento de segmentos curtos consecutivos do mesmo
// speaker. Whisper/gpt-4o-transcribe-diarize quebra a fala em chunks
// curtos (pausas naturais viram boundary), o que polui a transcrição
// com várias "caixas" pra falas tipo "Tudo certo, / Leandrão. / É o
// Doutor. / Gabriel, / por favor.". Agrupamos preservando timestamps
// (start do primeiro, end do último) — visual fica mais limpo e o
// karaokê continua funcionando porque o range do grupo cobre todas as
// sub-falas.
//
// Heurística adaptativa (iter 3 — feedback Leandro 2026-05-25 #2):
//   - SOFT_LIMIT (100): teto NORMAL — merges abaixo disso são livres.
//   - SHORT_THRESHOLD (30): chars que classificam um segment como
//     "curto" (ex: "né?", "Leandrão, então,", "Tudo certo,").
//   - HARD_LIMIT (300): teto absoluto — nem bolha de monólogo gigante
//     ultrapassa, pra UI não virar parágrafo único.
//
// REGRA: junta se MESMO SPEAKER, PROJECTED <= HARD_LIMIT, E qualquer:
//   (a) projected <= SOFT_LIMIT (caso comum) — OU
//   (b) segment ATUAL é curto (≤ 30) — absorve "né?" em qualquer fala
//       longa anterior — OU
//   (c) último do grupo era curto — uma intro tipo "Leandrão, então,"
//       deve absorver a fala longa que vem na sequência.
//
// Caso do bug reportado:
//   seg1 "Leandrão, então," (16 chars, CURTO) → grupo A
//   seg2 "me conta um pouquinho..." (162 chars, LONGO): same speaker;
//        último era curto → merge via (c). Grupo A: 179 chars.
//   seg3 "né?" (3 chars, CURTO): same speaker; atual é curto → merge
//        via (b). Grupo A: 183 chars. ≤ HARD_LIMIT → ok.
// Resultado: uma bolha só, igual o user pediu.
//
// Caso monólogo longo (5 chunks de 80 chars do mesmo speaker):
//   Nenhum chunk é curto, projected > SOFT_LIMIT → quebra a cada chunk.
//   UI continua respirável (5 bolhas de 80, não uma de 400).
const SOFT_LIMIT = 100;
const SHORT_THRESHOLD = 30;
const HARD_LIMIT = 300;

const speakerKeyOf = seg => String(seg?.speaker || '').toLowerCase();
const isShort = text => text.length <= SHORT_THRESHOLD;

const groupedSegments = computed(() => {
  const segs = props.segments || [];
  const out = [];
  for (let i = 0; i < segs.length; i += 1) {
    const seg = segs[i];
    const text = String(seg.text || '').trim();
    if (!text) continue;
    const last = out[out.length - 1];
    const sameSpeaker = last && speakerKeyOf(last) === speakerKeyOf(seg);
    const projected = sameSpeaker ? last.text.length + 1 + text.length : Infinity;
    const currentShort = isShort(text);
    const lastShort = sameSpeaker && isShort(last.text);

    const canMerge =
      sameSpeaker &&
      projected <= HARD_LIMIT &&
      (projected <= SOFT_LIMIT || currentShort || lastShort);

    if (canMerge) {
      last.text = `${last.text} ${text}`.replace(/\s+/g, ' ').trim();
      last.end = seg.end ?? last.end;
    } else {
      out.push({
        speaker: seg.speaker,
        text,
        start: seg.start,
        end: seg.end,
      });
    }
  }
  // Atribui `_id` estável depois do merge (DynamicScroller exige).
  return out.map((seg, i) => ({
    ...seg,
    _id: `${seg.start ?? i}-${seg.speaker || ''}-${i}`,
  }));
});

// Mantém nome `indexedSegments` pra não mexer no template + scroller.
const indexedSegments = groupedSegments;

// Binary search pelo segmento que contém `currentTime`. Segmentos do
// Whisper são monotonics por `start`, então busca binária é correta.
// Edge case: gap entre segments (end[i] < start[i+1]) → currentTime cai
// no "vácuo"; nesse caso retornamos o último segment cujo `start` é <=
// currentTime (mantém o destaque no último que falou, UX mais fluida que
// piscar para -1 a cada gap pequeno).
const activeIndex = computed(() => {
  const t = props.currentTime;
  const segs = indexedSegments.value;
  if (!segs.length || t <= 0) return -1;

  let lo = 0;
  let hi = segs.length - 1;
  let candidate = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >>> 1;
    const start = Number(segs[mid].start) || 0;
    if (start <= t) {
      candidate = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return candidate;
});

// Auto-scroll: sempre que activeIndex muda, scrolla o DynamicScroller pra
// manter o item visível — EXCETO se o usuário interagiu recentemente.
//
// 2026-05-25 (iter 2) — Em vez de scrollar pro item ativo direto (que
// fica colado no topo do viewport, perdendo contexto), miramos o
// item ANTERIOR. Resultado: a mensagem anterior fica visível em cima
// e o ativo aparece logo abaixo dela — UX igual letra de música, fácil
// de acompanhar onde a fala anterior terminou.
//
// Suavidade é via CSS `scroll-behavior: smooth` no container (regra
// no SCSS), pq `scrollToItem` da vue-virtual-scroller não tem
// flag de animação. Vantagem: respeita `prefers-reduced-motion` via
// media query no mesmo SCSS.
watch(activeIndex, (idx, oldIdx) => {
  if (idx < 0 || idx === oldIdx) return;
  if (Date.now() - userInteractedAt.value < USER_INTERACTION_GRACE_MS) return;
  const targetIdx = Math.max(0, idx - 1);
  scrollerRef.value?.scrollToItem?.(targetIdx);
});

// Cleanup defensivo do timestamp em unmount (não estritamente necessário,
// mas mantém o componente "limpo" se for remontado por keepalive).
onBeforeUnmount(() => {
  userInteractedAt.value = 0;
});

// Heurística de fala: o backend marca speaker como "doutor"/"paciente"
// (em PT-BR), mas aceitamos variações ("doctor", "DR", "patient").
const isDoctor = speaker => {
  const s = String(speaker || '').toLowerCase();
  return s.startsWith('d') || s === 'dr' || s === 'doctor';
};

const speakerLabel = seg =>
  isDoctor(seg.speaker) ? props.doctorName : props.patientName;

const speakerInitials = seg =>
  initialsFromName(isDoctor(seg.speaker) ? props.doctorName : props.patientName);

const speakerClass = seg =>
  isDoctor(seg.speaker)
    ? 'tcd-transcript__avatar--doctor'
    : 'tcd-transcript__avatar--patient';

const onSegmentActivate = seg => {
  // Clique direto pula o áudio pra esse trecho. Conta como interação manual
  // (zera grace), evitando que o auto-scroll imediatamente puxe pra outro
  // ponto antes do usuário ver o resultado do seek.
  markUserInteraction();
  emit('segment-click', seg);
};

// ─── Busca na transcrição (2026-05-25) ─────────────────────────────
// Input no toolbar filtra os grupos cujo texto contém a query (case-
// insensitive, trim). Navegação ↑/↓ entre matches, com auto-scroll pro
// match ativo (mesma regra de offset que o karaokê: scrollToItem(idx-1)).
// Highlight do termo dentro da bolha via <mark>.
//
// 2026-05-25 (iter 2) — UI estilo Spotify: estado colapsado é só uma
// lupa (botão quadrado 32×32); click expande horizontalmente revelando
// o input com transição suave. Click-fora ou Esc com input vazio
// colapsa de volta. Se tem query digitada, mantém aberto até clicar X.
const searchQuery = ref('');
const activeMatchIdx = ref(0);
const searchExpanded = ref(false);
const searchInputRef = ref(null);

const expandSearch = async () => {
  searchExpanded.value = true;
  // Focus no input depois do DOM atualizar (input só existe quando expandido)
  await new Promise(r => requestAnimationFrame(r));
  searchInputRef.value?.focus?.();
};
const collapseSearchIfEmpty = () => {
  if (!searchQuery.value) searchExpanded.value = false;
};

const normalizedQuery = computed(() => searchQuery.value.trim().toLowerCase());

const matches = computed(() => {
  const q = normalizedQuery.value;
  if (!q) return [];
  const out = [];
  const segs = indexedSegments.value;
  for (let i = 0; i < segs.length; i += 1) {
    if (String(segs[i].text).toLowerCase().includes(q)) out.push(i);
  }
  return out;
});

const activeMatchSegmentIdx = computed(() => matches.value[activeMatchIdx.value] ?? -1);

// Reset do cursor sempre que a query muda — começa do match 1.
watch(normalizedQuery, () => { activeMatchIdx.value = 0; });

// Scroll automático pro match ativo. Mesma lógica do karaokê: mira o
// item anterior pra dar contexto. Usuário não vai querer auto-scroll
// "roubando" enquanto digita; mas como ele explicitamente disparou a
// busca, podemos pular o grace period aqui.
watch(activeMatchSegmentIdx, idx => {
  if (idx < 0) return;
  const targetIdx = Math.max(0, idx - 1);
  scrollerRef.value?.scrollToItem?.(targetIdx);
});

const nextMatch = () => {
  if (!matches.value.length) return;
  activeMatchIdx.value = (activeMatchIdx.value + 1) % matches.value.length;
};
const prevMatch = () => {
  if (!matches.value.length) return;
  activeMatchIdx.value =
    (activeMatchIdx.value - 1 + matches.value.length) % matches.value.length;
};
const clearSearch = () => {
  searchQuery.value = '';
  searchExpanded.value = false;
};

// Escape de HTML pra não injetar tag (XSS) — o texto vem do LLM, então
// é "internal" mas devemos tratar como untrusted por defesa em profundidade.
const escapeHtml = str => String(str).replace(/[&<>"']/g, c => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]));
// Escape de meta-chars da regex pra que `q` literal não vire pattern.
const escapeRegex = str => String(str).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Retorna HTML escapado com `<mark>` envolvendo cada ocorrência da query.
// Marker ativo (no match selecionado) ganha classe extra `is-current`.
const highlightedText = (text, segmentIndex) => {
  const escapedText = escapeHtml(text);
  const q = normalizedQuery.value;
  if (!q) return escapedText;
  const escapedQ = escapeRegex(escapeHtml(q));
  // Regex insensible a caixa, captura preservando case original
  const re = new RegExp(`(${escapedQ})`, 'gi');
  const cls = segmentIndex === activeMatchSegmentIdx.value
    ? 'tcd-transcript__highlight is-current'
    : 'tcd-transcript__highlight';
  return escapedText.replace(re, `<mark class="${cls}">$1</mark>`);
};

// ─── Copiar transcrição (2026-05-25) ───────────────────────────────
// Botão com dropdown: copiar COM ou SEM timecode. Sempre identifica
// speaker pra contexto. Usa clipboard API moderna; em browser antigo
// (sem suporte) mostra feedback de erro.
const showCopyMenu = ref(false);
const copyFeedback = ref('');

const copyTranscript = async ({ withTimecode }) => {
  const lines = indexedSegments.value.map(seg => {
    const time = withTimecode ? `[${formatClockSeconds(seg.start)}] ` : '';
    return `${time}${speakerLabel(seg)}: ${seg.text}`;
  });
  const blob = lines.join('\n\n');
  try {
    await navigator.clipboard.writeText(blob);
    copyFeedback.value = withTimecode ? 'Copiado com timecode!' : 'Copiado!';
  } catch (e) {
    copyFeedback.value = 'Falha ao copiar';
  } finally {
    showCopyMenu.value = false;
    setTimeout(() => { copyFeedback.value = ''; }, 2200);
  }
};

// Click-fora fecha o menu de cópia e colapsa a busca se vazia.
const onDocClick = ev => {
  if (!ev.target.closest('.tcd-transcript-copy-wrap')) {
    showCopyMenu.value = false;
  }
  if (!ev.target.closest('.tcd-transcript-search')) {
    collapseSearchIfEmpty();
  }
};
onMounted(() => { document.addEventListener('click', onDocClick); });
// Vue 3 aceita múltiplos `onBeforeUnmount` callbacks; cada um é
// executado em ordem. Mais limpo que reuso de variável.
onBeforeUnmount(() => { document.removeEventListener('click', onDocClick); });
</script>

<template>
  <section class="tcd-card">
    <header class="tcd-transcript-toolbar">
      <h3 class="tcd-card__title tcd-transcript-toolbar__title">
        <i class="i-lucide-file-text w-5 h-5 tcd-card__title-icon" />
        <span>Transcrição</span>
      </h3>

      <div v-if="hasSegments" class="tcd-transcript-toolbar__actions">
        <!-- Busca (colapsa em só lupa quando vazia + sem foco) -->
        <div
          :class="[
            'tcd-transcript-search',
            {
              'is-expanded': searchExpanded,
              'has-query': searchQuery,
              'no-matches': searchQuery && matches.length === 0,
            }
          ]"
        >
          <button
            type="button"
            class="tcd-transcript-search__trigger"
            aria-label="Buscar na transcrição"
            @click="expandSearch"
          >
            <i class="i-lucide-search w-4 h-4" />
          </button>
          <input
            v-show="searchExpanded"
            ref="searchInputRef"
            v-model="searchQuery"
            type="text"
            placeholder="Buscar..."
            class="tcd-transcript-search__input"
            aria-label="Buscar na transcrição"
            @keydown.enter.prevent="nextMatch"
            @keydown.esc="clearSearch"
            @blur="collapseSearchIfEmpty"
          />
          <template v-if="searchExpanded">
            <span
              v-if="searchQuery && matches.length"
              class="tcd-transcript-search__counter"
              aria-live="polite"
            >
              {{ activeMatchIdx + 1 }}/{{ matches.length }}
            </span>
            <span
              v-else-if="searchQuery && !matches.length"
              class="tcd-transcript-search__counter tcd-transcript-search__counter--empty"
              aria-live="polite"
            >0/0</span>
            <div v-if="searchQuery && matches.length" class="tcd-transcript-search__nav">
              <button
                type="button"
                class="tcd-transcript-search__nav-btn"
                aria-label="Match anterior"
                @click="prevMatch"
              >
                <i class="i-lucide-chevron-up w-3.5 h-3.5" />
              </button>
              <button
                type="button"
                class="tcd-transcript-search__nav-btn"
                aria-label="Próximo match"
                @click="nextMatch"
              >
                <i class="i-lucide-chevron-down w-3.5 h-3.5" />
              </button>
            </div>
            <button
              v-if="searchQuery"
              type="button"
              class="tcd-transcript-search__clear"
              aria-label="Limpar busca"
              @click="clearSearch"
            >
              <i class="i-lucide-x w-3.5 h-3.5" />
            </button>
          </template>
        </div>

        <!-- Copiar -->
        <div class="tcd-transcript-copy-wrap">
          <button
            type="button"
            class="tcd-transcript-copy-btn"
            aria-label="Copiar transcrição"
            :aria-expanded="showCopyMenu"
            @click.stop="showCopyMenu = !showCopyMenu"
          >
            <i class="i-lucide-copy w-4 h-4" />
          </button>
          <div v-if="showCopyMenu" class="tcd-transcript-copy-menu" role="menu">
            <button
              type="button"
              class="tcd-transcript-copy-item"
              role="menuitem"
              @click="copyTranscript({ withTimecode: true })"
            >
              <i class="i-lucide-clock w-3.5 h-3.5" />
              <span>Copiar com timecode</span>
            </button>
            <button
              type="button"
              class="tcd-transcript-copy-item"
              role="menuitem"
              @click="copyTranscript({ withTimecode: false })"
            >
              <i class="i-lucide-align-left w-3.5 h-3.5" />
              <span>Copiar sem timecode</span>
            </button>
          </div>
          <div v-if="copyFeedback" class="tcd-transcript-copy-toast" role="status">
            {{ copyFeedback }}
          </div>
        </div>
      </div>
    </header>

    <DynamicScroller
      v-if="hasSegments"
      ref="scrollerRef"
      :items="indexedSegments"
      :min-item-size="80"
      key-field="_id"
      class="tcd-transcript tcd-transcript--virtual"
      @wheel.passive="markUserInteraction"
      @touchmove.passive="markUserInteraction"
    >
      <template #default="{ item: seg, index, active }">
        <DynamicScrollerItem
          :item="seg"
          :active="active"
          :data-index="index"
          :size-dependencies="[seg.text, searchQuery, activeMatchSegmentIdx]"
        >
          <div
            :class="[
              'tcd-transcript__msg',
              {
                'is-active': index === activeIndex,
                'is-match': matches.includes(index),
                'is-current-match': index === activeMatchSegmentIdx,
              }
            ]"
          >
            <div :class="['tcd-transcript__avatar', speakerClass(seg)]">
              {{ speakerInitials(seg) }}
            </div>
            <div class="tcd-transcript__body">
              <div class="tcd-transcript__head">
                <span>{{ speakerLabel(seg) }}</span>
                <span class="tcd-transcript__timestamp">{{ formatClockSeconds(seg.start) }}</span>
              </div>
              <!-- v-html é seguro aqui: highlightedText() escapa o input
                   via escapeHtml() antes de envolver os matches com <mark>.
                   Nenhum char do LLM passa sem escape. -->
              <p
                class="tcd-transcript__text"
                role="button"
                tabindex="0"
                v-html="highlightedText(seg.text, index)"
                @click="onSegmentActivate(seg)"
                @keydown.enter="onSegmentActivate(seg)"
              />
            </div>
          </div>
        </DynamicScrollerItem>
      </template>
    </DynamicScroller>

    <p v-else-if="text" class="tcd-transcript__text">{{ text }}</p>
    <p v-else class="tcd-transcript__empty">
      Transcrição ainda não disponível.
    </p>
  </section>
</template>

<style scoped>
/* DynamicScroller precisa de altura fixa pro viewport — sem isso o
   container colapsa e nada renderiza. 60vh dá scroll suficiente sem
   tomar a tela inteira do detalhe. Audit Fase 3.

   2026-05-25 (iter 2) — `scroll-behavior: smooth` deixa o auto-scroll
   do karaokê animado em vez de teletransportar entre segments. Só
   afeta scrolls programáticos (scrollToItem); wheel/touch continua
   com a velocidade nativa do usuário. */
.tcd-transcript--virtual {
  height: 60vh;
  min-height: 320px;
  max-height: 720px;
  overflow-y: auto;
  scroll-behavior: smooth;
}

@media (prefers-reduced-motion: reduce) {
  .tcd-transcript--virtual { scroll-behavior: auto; }
}
</style>
