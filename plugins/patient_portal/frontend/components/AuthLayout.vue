<template>
  <main class="pp-auth">
    <div class="pp-auth__card">
      <header class="pp-auth__header">
        <div class="pp-auth__brand">
          <span class="pp-auth__brand-dot" />Klivy
        </div>
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

<script setup>
defineProps({ title: String, subtitle: String });
</script>

<style scoped>
.pp-auth {
  min-height: 100vh; display: flex; flex-direction: column;
  align-items: center; justify-content: center; gap: 16px;
  padding: 24px;
  background:
    radial-gradient(ellipse at top, rgba(37,99,235,.08) 0%, transparent 50%),
    linear-gradient(180deg, #f8fafc 0%, #eef2ff 100%);
}
.pp-auth__card {
  width: 100%; max-width: 420px;
  background: #fff; border: 1px solid var(--pp-color-border);
  border-radius: 24px; padding: 32px;
  box-shadow: 0 12px 40px rgba(15, 23, 42, .08), 0 1px 3px rgba(15, 23, 42, .04);
}
.pp-auth__header { margin-bottom: 24px; text-align: center; }
.pp-auth__brand {
  display: inline-flex; align-items: center; gap: 6px;
  font-weight: 700; font-size: 12px; letter-spacing: 2px;
  color: var(--pp-color-primary); margin-bottom: 18px;
  padding: 6px 12px; border-radius: 999px;
  background: rgba(37, 99, 235, .08);
}
.pp-auth__brand-dot {
  width: 6px; height: 6px; border-radius: 50%;
  background: var(--pp-color-primary);
  box-shadow: 0 0 0 4px rgba(37, 99, 235, .15);
}
.pp-auth__title    { margin: 0; font-size: 22px; font-weight: 700; color: var(--pp-color-text); }
.pp-auth__subtitle { margin: 8px 0 0; font-size: 14px; color: var(--pp-color-text-muted); }
.pp-auth__legal    { margin: 0; font-size: 12px; color: var(--pp-color-text-muted); text-align: center; }
</style>
