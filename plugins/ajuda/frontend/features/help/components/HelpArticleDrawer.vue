<script setup>
import { ref, watch, computed, onMounted, onUnmounted } from 'vue';

const props = defineProps({
  data: { type: Object, default: null },
});
const emit = defineEmits(['close', 'openArticle', 'openChat']);

const helpfulVote = ref(null);
const expanded    = ref(false);
const articleIframe = ref(null);
let resizeObserver = null;

watch(() => props.data, () => {
  helpfulVote.value = null;
  expanded.value = false;
});

function onBackdropKey(e) {
  if (e.key === 'Escape' && props.data) emit('close');
}
onMounted(() => window.addEventListener('keydown', onBackdropKey));
onUnmounted(() => {
  window.removeEventListener('keydown', onBackdropKey);
  if (resizeObserver) { resizeObserver.disconnect(); resizeObserver = null; }
});

function openArticle(cat, art) {
  emit('openArticle', cat, art);
}

const videoEmbedUrl = computed(() => {
  const url = props.data?.art?.videoUrl;
  if (!url) return null;
  const yt = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\s]+)/);
  const vi = url.match(/vimeo\.com\/(\d+)/);
  if (yt) return `https://www.youtube.com/embed/${yt[1]}`;
  if (vi) return `https://player.vimeo.com/video/${vi[1]}`;
  return null;
});

const nextStepsList = computed(() => {
  const raw = props.data?.art?.nextSteps ?? '';
  return raw.split('\n').map(s => s.trim()).filter(Boolean);
});

const FRAGMENT_BASE_CSS = `
  html, body { margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Roboto, sans-serif;
    color: #1f2937;
    line-height: 1.7;
    font-size: 15px;
    word-wrap: break-word;
  }
  p { margin: 0 0 14px; }
  h1, h2, h3 { color: #0f172a; }
  h2 { font-size: 1.15em; font-weight: 700; margin: 22px 0 10px; }
  h3 { font-size: 1em; font-weight: 600; margin: 18px 0 8px; }
  ul, ol { padding-left: 20px; margin: 8px 0 14px; }
  li { margin-bottom: 4px; }
  blockquote { border-left: 3px solid #2c5cc5; padding-left: 14px; color: #475569; margin: 14px 0; }
  a { color: #2c5cc5; text-decoration: underline; }
  img, video, iframe { max-width: 100%; height: auto; border-radius: 8px; }
  pre, code { background: #f3f4f6; border-radius: 4px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  code { padding: 2px 6px; font-size: 0.9em; }
  pre { padding: 12px 14px; overflow-x: auto; }
  pre code { background: none; padding: 0; }
`;

const articleSrcdoc = computed(() => {
  const html = typeof props.data?.art?.body === 'string' ? props.data.art.body : '';
  if (!html) return '';
  const isFullDoc = /^\s*<(!doctype|html\b)/i.test(html);
  if (isFullDoc) return html;
  return `<!DOCTYPE html><html lang="pt-BR"><head>` +
    `<meta charset="UTF-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1.0">` +
    `<base target="_parent">` +
    `<style>${FRAGMENT_BASE_CSS}</style>` +
    `</head><body>${html}</body></html>`;
});

function syncIframeHeight() {
  const iframe = articleIframe.value;
  const doc = iframe?.contentDocument;
  if (!iframe || !doc?.body) return;
  // Mede pelo body, não pelo documentElement, para não herdar `min-height: 100vh`
  // que muitos resets de CSS dos artigos aplicam (e que faria o iframe crescer
  // até a altura da viewport, deixando um vão grande embaixo do conteúdo).
  iframe.style.height = `${doc.body.scrollHeight}px`;
}

function onIframeLoad() {
  if (resizeObserver) { resizeObserver.disconnect(); resizeObserver = null; }
  const iframe = articleIframe.value;
  const doc = iframe?.contentDocument;
  if (!iframe || !doc?.documentElement) return;

  // Injeta um reset CSS no fim do <head> do artigo para neutralizar regras como
  // `html, body { min-height: 100vh }` que vêm do CSS do autor e inflam o
  // scrollHeight da página. A regra é `!important` para vencer o CSS do autor.
  if (doc.head && !doc.getElementById('__klivy_iframe_fit__')) {
    const reset = doc.createElement('style');
    reset.id = '__klivy_iframe_fit__';
    reset.textContent =
      'html,body{height:auto!important;min-height:0!important;}' +
      'body{margin:0!important;}';
    doc.head.appendChild(reset);
  }

  syncIframeHeight();
  if (typeof ResizeObserver !== 'undefined') {
    resizeObserver = new ResizeObserver(syncIframeHeight);
    resizeObserver.observe(doc.body);
  }
}
</script>

<template>
  <Teleport to="body">
    <Transition name="hp-fade">
      <div v-if="data" class="hp-drawer-backdrop" @click="emit('close')" />
    </Transition>

    <Transition name="hp-slide">
      <aside v-if="data" :class="['hp-drawer', expanded && 'hp-drawer--expanded']">
        <div class="hp-drawer-head">
          <button class="hp-drawer-back-btn" @click="emit('close')">
            <span class="i-lucide-arrow-left" style="font-size: 15px;" />
            Voltar
          </button>

          <div style="display: flex; align-items: center; gap: 8px; margin-left: auto;">
            <span v-if="data.kind === 'article'" class="hp-drawer-pill">
              {{ data.cat.name }}
            </span>
            <span v-else-if="data.kind === 'category'" class="hp-drawer-pill">
              {{ data.cat.count }} artigos
            </span>

            <button
              v-if="data.kind === 'article'"
              class="hp-drawer-expand-btn"
              :title="expanded ? 'Modo compacto' : 'Modo leitura'"
              @click="expanded = !expanded"
            >
              <span :class="expanded ? 'i-lucide-minimize-2' : 'i-lucide-maximize-2'" style="font-size: 15px;" />
            </button>
          </div>
        </div>

        <div :class="['hp-drawer-body', data.kind === 'article' && 'hp-drawer-body--article']">
          <!-- Article view -->
          <template v-if="data.kind === 'article'">
            <h1>{{ data.art.title }}</h1>
            <div class="hp-art-meta">
              <span class="hp-art-meta-item">
                <span class="i-lucide-clock" style="font-size: 12px;" />
                {{ data.art.time || 'Leitura rápida' }}
              </span>
              <span>Atualizado em abr 2026</span>
            </div>

            <!-- Video embed -->
            <div v-if="videoEmbedUrl" class="hp-art-video">
              <iframe
                :src="videoEmbedUrl"
                frameborder="0"
                allowfullscreen
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              />
            </div>

            <template v-if="data.art.body">
              <template v-if="typeof data.art.body === 'string'">
                <iframe
                  ref="articleIframe"
                  class="hp-art-iframe"
                  :srcdoc="articleSrcdoc"
                  sandbox="allow-same-origin allow-popups"
                  referrerpolicy="no-referrer"
                  loading="lazy"
                  title="Conteúdo do artigo"
                  @load="onIframeLoad"
                />
              </template>
              <template v-else>
                <p v-for="(paragraph, i) in data.art.body" :key="i">{{ paragraph }}</p>
              </template>
            </template>
            <template v-else>
              <p>Este artigo está sendo finalizado pela nossa equipe de conteúdo. Em breve você terá um passo a passo completo aqui.</p>
              <p>Enquanto isso, fale com nosso time pelo chat para tirar essa dúvida específica — respondemos em poucos minutos.</p>
            </template>

            <!-- Next steps (only shown when set in Super Admin) -->
            <template v-if="nextStepsList.length > 0">
              <h2>Próximos passos</h2>
              <ul>
                <li v-for="(step, i) in nextStepsList" :key="i">{{ step }}</li>
              </ul>
            </template>

            <div class="hp-helpful">
              <div class="hp-helpful-q">Esse artigo foi útil?</div>
              <div class="hp-helpful-btns">
                <button
                  :class="['hp-btn-ghost', helpfulVote === 'yes' && 'hp-voted']"
                  @click="helpfulVote = 'yes'"
                >
                  <span class="i-lucide-thumbs-up" style="font-size: 14px;" />
                  Sim
                </button>
                <button
                  :class="['hp-btn-ghost', helpfulVote === 'no' && 'hp-voted']"
                  @click="helpfulVote = 'no'"
                >
                  <span class="i-lucide-thumbs-down" style="font-size: 14px;" />
                  Não
                </button>
              </div>
              <div v-if="helpfulVote" class="hp-helpful-ack">
                {{ helpfulVote === 'yes' ? 'Obrigado pelo feedback!' : 'Vamos melhorar — seu retorno foi enviado.' }}
              </div>
            </div>
          </template>

          <!-- Category view -->
          <template v-else-if="data.kind === 'category'">
            <h1>{{ data.cat.name }}</h1>
            <p>{{ data.cat.description }}</p>
            <h2 style="margin-top: 24px;">Todos os artigos</h2>

            <div v-if="data.cat.articles && data.cat.articles.length > 0" class="hp-art-list">
              <button
                v-for="art in data.cat.articles"
                :key="art.id"
                class="hp-art-list-item"
                @click="openArticle(data.cat, art)"
              >
                <div class="hp-art-list-icon">
                  <span class="i-lucide-file-text" />
                </div>
                <div>
                  <div class="hp-art-list-title">{{ art.title }}</div>
                  <div class="hp-art-list-time">{{ art.time || 'Leitura rápida' }}</div>
                </div>
                <span class="hp-art-list-chev i-lucide-chevron-right" style="margin-left: auto;" />
              </button>
            </div>

            <div v-else class="hp-empty-state">
              <div class="hp-empty-state-icon">
                <span class="i-lucide-file-search" style="font-size: 28px;" />
              </div>
              <h3 class="hp-empty-state-title">Ainda não há artigos nesta categoria</h3>
              <p class="hp-empty-state-text">
                Estamos preparando o conteúdo. Enquanto isso, fale com nosso time
                — respondemos em poucos minutos.
              </p>
              <button class="hp-empty-state-btn" @click="emit('openChat')">
                <span class="i-lucide-message-circle" style="font-size: 14px;" />
                Falar com suporte
              </button>
            </div>
          </template>
        </div>
      </aside>
    </Transition>
  </Teleport>
</template>
