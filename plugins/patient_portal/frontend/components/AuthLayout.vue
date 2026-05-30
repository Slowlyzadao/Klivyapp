<script setup>
import KlivyLogo from './KlivyLogo.vue';
defineProps({ title: String, subtitle: String });
</script>

<template>
  <main class="pp-auth">
    <div class="pp-auth__card">
      <header class="pp-auth__header">
        <KlivyLogo variant="full" class="pp-auth__brand" />
        <h1 class="pp-auth__title">{{ title }}</h1>
        <p v-if="subtitle" class="pp-auth__subtitle">{{ subtitle }}</p>
      </header>
      <slot />
    </div>
    <p class="pp-auth__legal">
      Portal do Paciente · Atendimento omnichannel com gestão clínica
    </p>
  </main>
</template>

<style scoped>
.pp-auth {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  padding: 24px;
  background: radial-gradient(
      ellipse at top,
      rgba(37, 99, 235, 0.08) 0%,
      transparent 50%
    ),
    linear-gradient(180deg, #f8fafc 0%, #eef2ff 100%);
}
.pp-auth__card {
  width: 100%;
  max-width: 420px;
  background: #fff;
  border: 1px solid var(--pp-color-border);
  border-radius: 24px;
  padding: 32px;
  box-shadow:
    0 12px 40px rgba(15, 23, 42, 0.08),
    0 1px 3px rgba(15, 23, 42, 0.04);
}
@media (min-width: 1024px) {
  .pp-auth__card {
    max-width: 460px;
    padding: 40px;
  }
  .pp-auth__title {
    font-size: 24px;
  }
}
.pp-auth__header {
  margin-bottom: 24px;
  text-align: center;
}
.pp-auth__brand {
  margin-bottom: 20px;
  height: 44px;
}
@media (min-width: 1024px) {
  .pp-auth__brand {
    height: 52px;
    margin-bottom: 24px;
  }
}
.pp-auth__title {
  margin: 0;
  font-size: 22px;
  font-weight: 700;
  color: var(--pp-color-text);
}
.pp-auth__subtitle {
  margin: 8px 0 0;
  font-size: 14px;
  color: var(--pp-color-text-muted);
}
.pp-auth__legal {
  margin: 0;
  font-size: 12px;
  color: var(--pp-color-text-muted);
  text-align: center;
}
</style>
