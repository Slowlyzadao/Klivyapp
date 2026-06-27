<template>
  <router-view v-slot="{ Component }">
    <transition name="pp-fade" mode="out-in">
      <component :is="Component" />
    </transition>
  </router-view>
</template>

<script setup>
// Raiz do SPA. Transição de fade suave entre rotas — ajuda na sensação
// de app nativo. Lógica fica nas pages e nos stores.
</script>

<style>
/* Transições — declaradas como global pra funcionar com lazy-loaded components */
.pp-fade-enter-active,
.pp-fade-leave-active {
  transition: opacity 180ms ease, transform 180ms ease;
}
.pp-fade-enter-from { opacity: 0; transform: translateY(4px); }
.pp-fade-leave-to   { opacity: 0; transform: translateY(-4px); }
</style>
