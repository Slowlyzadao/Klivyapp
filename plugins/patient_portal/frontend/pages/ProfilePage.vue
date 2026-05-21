<template>
  <AppShell>
    <PageHeader title="Meu perfil" back @back="$router.back()" />

    <div v-if="profile.loading" class="pp-prof__loading">Carregando…</div>

    <form v-else class="pp-prof" @submit.prevent="onSubmit">
      <BaseCard title="Dados pessoais">
        <BaseInput v-model="form.name"      label="Nome completo" />
        <BaseInput v-model="form.email"     label="E-mail" type="email" autocomplete="email" />
        <BaseInput v-model="form.phone"     label="Telefone" autocomplete="tel" />
        <BaseInput v-model="form.birthdate" label="Data de nascimento" type="date" />

        <label class="pp-prof__field">
          <span class="pp-prof__label">Sexo</span>
          <select v-model="form.sex" class="pp-prof__select">
            <option value="">Prefiro não informar</option>
            <option value="masculino">Masculino</option>
            <option value="feminino">Feminino</option>
            <option value="outro">Outro</option>
          </select>
        </label>
      </BaseCard>

      <BaseCard title="Endereço">
        <BaseInput v-model="form.address.street"       label="Rua" />
        <div class="pp-prof__row">
          <BaseInput v-model="form.address.number"       label="Número" />
          <BaseInput v-model="form.address.complement"   label="Complemento" />
        </div>
        <BaseInput v-model="form.address.neighborhood" label="Bairro" />
        <div class="pp-prof__row">
          <BaseInput v-model="form.address.city"  label="Cidade" />
          <BaseInput v-model="form.address.state" label="UF" />
        </div>
        <BaseInput v-model="form.address.zip_code" label="CEP" />
      </BaseCard>

      <p v-if="profile.error" class="pp-prof__error">{{ profile.error }}</p>
      <p v-if="saved"          class="pp-prof__success">Dados atualizados ✓</p>

      <BaseButton block size="lg" type="submit" :loading="profile.saving">
        Salvar alterações
      </BaseButton>
    </form>
  </AppShell>
</template>

<script setup>
import { ref, watch, onMounted } from 'vue';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import BaseCard from '../components/BaseCard.vue';
import BaseInput from '../components/BaseInput.vue';
import BaseButton from '../components/BaseButton.vue';
import { useProfileStore } from '../store/profile';

const profile = useProfileStore();
const saved   = ref(false);

const form = ref({
  name: '', email: '', phone: '', birthdate: '', sex: '',
  address: { street: '', number: '', complement: '', neighborhood: '', city: '', state: '', zip_code: '' }
});

function hydrate(d) {
  form.value = {
    name:      d.name      || '',
    email:     d.email     || '',
    phone:     d.phone     || '',
    birthdate: d.birthdate || '',
    sex:       d.sex       || '',
    address: {
      street:       d.address?.street       || '',
      number:       d.address?.number       || '',
      complement:   d.address?.complement   || '',
      neighborhood: d.address?.neighborhood || '',
      city:         d.address?.city         || '',
      state:        d.address?.state        || '',
      zip_code:     d.address?.zip_code     || ''
    }
  };
}

onMounted(async () => {
  await profile.fetch();
  if (profile.data) hydrate(profile.data);
});
watch(() => profile.data, (d) => { if (d) hydrate(d); });

async function onSubmit() {
  saved.value = false;
  try {
    await profile.save(form.value);
    saved.value = true;
    setTimeout(() => { saved.value = false; }, 3000);
  } catch (_) { /* erro fica em store */ }
}
</script>

<style scoped>
.pp-prof { padding: 16px; display: flex; flex-direction: column; gap: 16px; }
.pp-prof__loading { padding: 32px; text-align: center; color: var(--pp-color-text-muted); font-size: 14px; }

.pp-prof__row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }

.pp-prof__field { display: flex; flex-direction: column; gap: 6px; margin-top: 12px; }
.pp-prof__label { font-size: 12px; font-weight: 600; color: var(--pp-color-text-muted); }
.pp-prof__select {
  padding: 10px 12px; border-radius: 10px;
  border: 1px solid var(--pp-color-border); font-size: 14px; font-family: inherit;
}

.pp-prof__error   { color: #b91c1c; font-size: 13px; margin: 0; text-align: center; }
.pp-prof__success { color: #047857; font-size: 13px; margin: 0; text-align: center; font-weight: 600; }
</style>
