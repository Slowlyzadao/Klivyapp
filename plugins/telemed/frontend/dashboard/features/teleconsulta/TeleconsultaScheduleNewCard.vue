<script setup>
// Placeholder "Agendar nova" exibido no fim da grid de teleconsultas.
// Sem lógica própria — emite `click` para o pai redirecionar ao fluxo
// de novo agendamento (a integração será definida na próxima tela).
defineEmits(['click']);
</script>

<template>
  <div class="tc-card-new" @click="$emit('click')">
    <span class="tc-card-new__icon">
      <i class="i-lucide-plus-circle w-8 h-8" />
    </span>
    <h3 class="tc-card-new__title">Agendar Nova</h3>
    <p class="tc-card-new__hint">
      Crie um link de teleconsulta instantâneo ou agende para depois.
    </p>
    <button
      type="button"
      class="tc-card-new__cta"
      @click.stop="$emit('click')"
    >
      Agendar Consulta
    </button>
  </div>
</template>
