<template>
  <div v-if="show" class="pp-acting">
    <Avatar :name="activeName" size="sm" />
    <div class="pp-acting__body">
      <div class="pp-acting__line1">Acessando <strong>{{ activeName }}</strong></div>
      <div class="pp-acting__line2">você ({{ actingName }}) como responsável</div>
    </div>
    <router-link :to="{ name: 'more' }" class="pp-acting__cta">Trocar</router-link>
  </div>
</template>

<script setup>
// Banner persistente no topo das telas quando o acting está agindo em nome
// de um dependente (Sprint I).
//
// Mantemos visível pra evitar engano de identidade — o paciente nunca esquece
// que está atuando como responsável.
import { computed, onMounted } from 'vue';
import { useDependentsStore } from '../store/dependents';
import Avatar from './Avatar.vue';

const deps = useDependentsStore();

onMounted(() => {
  if (!deps.acting) deps.fetch();
});

const show       = computed(() => deps.onDependent);
const activeName = computed(() => deps.active?.name || '');
const actingName = computed(() => deps.acting?.name || '');
</script>

<style scoped>
.pp-acting {
  display: flex; align-items: center; gap: 10px;
  margin: 8px 16px 12px; padding: 10px 12px;
  background: linear-gradient(90deg, #ecfdf5, #d1fae5);
  border: 1px solid #6ee7b7; border-radius: 12px;
}
.pp-acting__body  { flex: 1; min-width: 0; font-size: 12px; color: #065f46; }
.pp-acting__line1 { font-weight: 600; }
.pp-acting__line2 { opacity: 0.85; margin-top: 1px; }
.pp-acting__cta   {
  font-size: 12px; font-weight: 600; color: #065f46;
  background: #fff; padding: 6px 10px; border-radius: 8px;
  text-decoration: none; border: 1px solid #6ee7b7;
}
</style>
