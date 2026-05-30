<script setup>
import logoUrl from '../assets/logo/logo_completo.svg';
</script>

<template>
  <img
    :src="logoUrl"
    class="pp-klivy-logo"
    alt="Klivy Você"
    width="801"
    height="270"
  />
</template>

<style scoped>
/* Altura controlada pelo parent. Width auto preserva proporção 801:270. */
.pp-klivy-logo {
  height: 32px;
  width: auto;
  display: block;
}
</style>
