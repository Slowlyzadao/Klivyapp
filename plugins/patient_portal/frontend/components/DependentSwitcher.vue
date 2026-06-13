<template>
  <section class="pp-dep">
    <header class="pp-dep__header">
      <div>
        <h3 class="pp-dep__title">Quem você está acessando?</h3>
        <p class="pp-dep__subtitle">
          Você é responsável por outros pacientes desta clínica. Escolha quem acessar agora.
        </p>
      </div>
    </header>

    <div class="pp-dep__list">
      <button
        v-for="p in deps.accessible"
        :key="p.id"
        type="button"
        class="pp-dep__item"
        :class="{ 'pp-dep__item--active': isActive(p) }"
        :disabled="deps.switching"
        @click="onSwitch(p)"
      >
        <Avatar :name="p.name" size="md" />
        <div class="pp-dep__item-body">
          <div class="pp-dep__item-name">{{ p.name }}</div>
          <div class="pp-dep__item-tag">{{ p.is_self ? 'Você' : 'Dependente' }}</div>
        </div>
        <span v-if="isActive(p)" class="pp-dep__check">✓</span>
      </button>
    </div>

    <p v-if="deps.error" class="pp-dep__error">{{ deps.error }}</p>
  </section>
</template>

<script setup>
// Switcher de paciente acessado (Sprint I).
//
// Componente "burro" — toda a regra de quem pode acessar quem mora no
// backend (`PatientPortal::SessionContext`). Front só lê `accessible` e
// dispara switch via store.
import { onMounted } from 'vue';
import { useDependentsStore } from '../store/dependents';
import Avatar from './Avatar.vue';

const deps = useDependentsStore();

onMounted(() => {
  if (!deps.acting) deps.fetch();
});

function isActive(p) {
  return deps.active?.id === p.id;
}

async function onSwitch(p) {
  if (isActive(p)) return;
  const ok = await deps.switchTo(p.id);
  if (ok) {
    // Recarrega a página para que todas as stores (auth/home/etc) refleitam o paciente novo.
    window.location.reload();
  }
}
</script>

<style scoped>
.pp-dep {
  margin: 0 16px 20px; padding: 16px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 16px;
}
.pp-dep__header { margin-bottom: 12px; }
.pp-dep__title  { margin: 0; font-size: 15px; font-weight: 700; color: var(--pp-color-text); }
.pp-dep__subtitle { margin: 4px 0 0; font-size: 12px; color: var(--pp-color-text-muted); line-height: 1.4; }

.pp-dep__list  { display: grid; gap: 8px; }
.pp-dep__item  {
  display: flex; align-items: center; gap: 12px;
  padding: 10px 12px; background: #fff;
  border: 1px solid var(--pp-color-border); border-radius: 12px;
  cursor: pointer; text-align: left;
  transition: border-color 120ms ease, background 120ms ease;
}
.pp-dep__item:disabled { opacity: 0.5; cursor: not-allowed; }
.pp-dep__item:not(:disabled):hover { border-color: var(--pp-color-primary); }

.pp-dep__item--active {
  border-color: var(--pp-color-primary);
  background: rgba(37, 99, 235, 0.05);
}

.pp-dep__item-body  { flex: 1; min-width: 0; }
.pp-dep__item-name  { font-size: 14px; font-weight: 600; color: var(--pp-color-text); }
.pp-dep__item-tag   { font-size: 11px; color: var(--pp-color-text-muted); margin-top: 2px; text-transform: uppercase; letter-spacing: 0.5px; }
.pp-dep__check      { color: var(--pp-color-primary); font-size: 18px; font-weight: 700; }

.pp-dep__error { margin: 10px 0 0; font-size: 12px; color: #b91c1c; }
</style>
