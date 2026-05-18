<script setup>
import { ref, watch, computed, onMounted, onUnmounted } from 'vue';

const props = defineProps({
  data: { type: Object, default: null },
});
const emit = defineEmits(['close', 'openArticle', 'openChat']);

const helpfulVote = ref(null);
const expanded    = ref(false);

watch(() => props.data, () => {
  helpfulVote.value = null;
  expanded.value = false;
});

function onBackdropKey(e) {
  if (e.key === 'Escape' && props.data) emit('close');
}
onMounted(() => window.addEventListener('keydown', onBackdropKey));
onUnmounted(() => window.removeEventListener('keydown', onBackdropKey));

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

        <div class="hp-drawer-body">
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
                <!-- eslint-disable-next-line vue/no-v-html -->
                <div class="hp-art-body" v-html="data.art.body" />
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
            <p style="color: rgb(var(--slate-10));">{{ data.cat.description }}</p>
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
