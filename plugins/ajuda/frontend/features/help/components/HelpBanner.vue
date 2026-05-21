<script setup>
defineEmits(['openChat']);
</script>

<template>
  <div class="hp-banner">
    <div class="hp-banner-icon">
      <span class="i-lucide-message-circle" />
    </div>
    <div class="hp-banner-text">
      <div class="hp-banner-title">Precisa de ajuda? Fale com o nosso time agora.</div>
      <div class="hp-banner-sub">Tempo médio de resposta: 2 minutos · 100% em português</div>
    </div>
    <button class="hp-btn-primary" @click="$emit('openChat')">
      <span class="i-lucide-message-circle" style="font-size: 14px;" />
      Iniciar conversa
    </button>
  </div>
</template>
