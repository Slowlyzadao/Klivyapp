<script setup>
// Tela "Dados da clínica" (Configurações). Grava em account.custom_attributes
// + anexo de logo (ActiveStorage), via o endpoint clinic_profile. Esses dados
// alimentam as variáveis clinic.* dos documentos (CNPJ, endereço, logo, etc.).
// Não cria tabela nova; o checkout (compra) não é tocado — admin completa aqui.

import { ref, reactive, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { usePermissions } from 'dashboard/composables/usePermissions';
import { uploadFile } from 'dashboard/helper/uploadHelper';
import {
  maskCpf,
  maskCnpj,
  maskPhone,
  maskCep,
} from '@plugins/beclinic_core/frontend/utils/documentMasks';
import AccountAPI from 'dashboard/api/account';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SectionLayout from '../account/components/SectionLayout.vue';

const { t } = useI18n();
const { isAdmin, can: klivyCan } = usePermissions();

const canManage = computed(
  () => isAdmin.value || klivyCan('settings', 'account_manage')
);

const form = reactive({
  fantasy_name: '',
  cnpj: '',
  phone: '',
  website: '',
  address_zip: '',
  address_street: '',
  address_number: '',
  address_complement: '',
  address_neighborhood: '',
  address_city: '',
  address_state: '',
});

const logoUrl = ref('');
const logoBlobId = ref(null);
const uploadingLogo = ref(false);
const loading = ref(true);
const saving = ref(false);
const logoInput = ref(null);

const ADDRESS_FIELDS = [
  'address_zip',
  'address_street',
  'address_number',
  'address_complement',
  'address_neighborhood',
  'address_city',
  'address_state',
];

const labelFor = key => t(`CLINIC_SETTINGS.FORM.${key.toUpperCase()}.LABEL`);
const placeholderFor = key =>
  t(`CLINIC_SETTINGS.FORM.${key.toUpperCase()}.PLACEHOLDER`);

// UF: 2 letras maiúsculas.
const maskUf = v =>
  String(v || '')
    .replace(/[^a-zA-Z]/g, '')
    .toUpperCase()
    .slice(0, 2);

// Máscaras por campo (funções puras do beclinic_core). Backend normaliza pra
// dígitos de qualquer forma, então gravamos o valor mascarado sem problema.
const MASKS = {
  phone: maskPhone,
  address_zip: maskCep,
  address_state: maskUf,
};

const applyMask = (key, value) => (MASKS[key] ? MASKS[key](value) : value);

const onlyDigits = v => String(v || '').replace(/\D/g, '');

// ── Documento da clínica: PF (CPF) ou PJ (CNPJ) ─────────────────────────
// Toggle explícito + auto-detecção pelo tamanho ao carregar (≤11 díg = CPF).
// Gravado em custom_attributes.cnpj (chave do ClinicReader) seja CPF ou CNPJ.
const docType = ref('cnpj');
const detectDocType = v => (onlyDigits(v).length <= 11 ? 'cpf' : 'cnpj');
const maskDoc = v => (docType.value === 'cpf' ? maskCpf(v) : maskCnpj(v));
const onCnpjInput = v => {
  form.cnpj = maskDoc(v);
};
const setDocType = type => {
  docType.value = type;
  form.cnpj = maskDoc(form.cnpj);
};

// ── CEP autofill (ViaCEP) — igual ao cadastro de paciente/checkout ──────
const lookupCep = async () => {
  const cep = onlyDigits(form.address_zip);
  if (cep.length !== 8) return;
  try {
    const resp = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
    const data = await resp.json();
    if (data.erro) return;
    if (data.logradouro) form.address_street = data.logradouro;
    if (data.bairro) form.address_neighborhood = data.bairro;
    if (data.localidade) form.address_city = data.localidade;
    if (data.uf) form.address_state = data.uf;
  } catch (e) {
    /* offline / ViaCEP fora → preenche manual */
  }
};

const onFieldInput = (key, value) => {
  form[key] = applyMask(key, value);
  if (key === 'address_zip' && onlyDigits(form.address_zip).length === 8) {
    lookupCep();
  }
};

onMounted(async () => {
  try {
    const { data } = await AccountAPI.getClinicProfile();
    docType.value = detectDocType(data.cnpj);
    Object.keys(form).forEach(k => {
      form[k] =
        k === 'cnpj' ? maskDoc(data.cnpj || '') : applyMask(k, data[k] || '');
    });
    logoUrl.value = data.logo_url || '';
  } catch (e) {
    useAlert(t('CLINIC_SETTINGS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
});

const pickLogo = () => logoInput.value?.click();

const onLogoChange = async e => {
  const file = e.target.files?.[0];
  if (!file) return;
  if (!file.type.startsWith('image/')) {
    useAlert(t('CLINIC_SETTINGS.LOGO_TYPE_ERROR'));
    return;
  }
  uploadingLogo.value = true;
  try {
    const { fileUrl, blobId } = await uploadFile(file);
    logoBlobId.value = blobId;
    logoUrl.value = fileUrl;
  } catch (err) {
    useAlert(t('CLINIC_SETTINGS.LOGO_ERROR'));
  } finally {
    uploadingLogo.value = false;
    if (e.target) e.target.value = '';
  }
};

const save = async () => {
  saving.value = true;
  try {
    const payload = { ...form };
    if (logoBlobId.value) payload.blob_id = logoBlobId.value;
    const { data } = await AccountAPI.updateClinicProfile(payload);
    logoUrl.value = data.logo_url || logoUrl.value;
    logoBlobId.value = null;
    useAlert(t('CLINIC_SETTINGS.SAVE_SUCCESS'));
  } catch (e) {
    useAlert(t('CLINIC_SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col w-full max-w-2xl ltr:mr-auto rtl:ml-auto">
    <BaseSettingsHeader
      :title="$t('CLINIC_SETTINGS.TITLE')"
      :description="$t('CLINIC_SETTINGS.DESCRIPTION')"
    />

    <div class="flex-grow flex-shrink min-w-0 mt-3">
      <woot-loading-state v-if="loading" />

      <form v-else class="flex flex-col" @submit.prevent="save">
        <SectionLayout
          :title="$t('CLINIC_SETTINGS.IDENTITY_SECTION.TITLE')"
          :description="$t('CLINIC_SETTINGS.IDENTITY_SECTION.NOTE')"
          class="!pt-0"
        >
          <div class="grid gap-4">
            <!-- Logo -->
            <WithLabel :label="$t('CLINIC_SETTINGS.FORM.LOGO.LABEL')">
              <div class="flex items-center gap-4">
                <div
                  class="flex items-center justify-center w-20 h-20 overflow-hidden border rounded-lg bg-n-slate-2 border-n-slate-4 shrink-0"
                >
                  <img
                    v-if="logoUrl"
                    :src="logoUrl"
                    alt="logo"
                    class="object-contain w-full h-full"
                  />
                  <span v-else class="w-6 h-6 i-lucide-image text-n-slate-9" />
                </div>
                <input
                  ref="logoInput"
                  type="file"
                  accept="image/png,image/jpeg,image/webp,image/svg+xml"
                  class="hidden"
                  @change="onLogoChange"
                />
                <NextButton
                  type="button"
                  slate
                  faded
                  :is-loading="uploadingLogo"
                  @click="pickLogo"
                >
                  {{ $t('CLINIC_SETTINGS.FORM.LOGO.UPLOAD') }}
                </NextButton>
              </div>
            </WithLabel>

            <WithLabel :label="labelFor('fantasy_name')">
              <NextInput
                v-model="form.fantasy_name"
                type="text"
                class="w-full"
                :placeholder="placeholderFor('fantasy_name')"
              />
            </WithLabel>

            <!-- CPF / CNPJ — a clínica pode ser PF ou PJ. -->
            <WithLabel
              :label="
                docType === 'cpf'
                  ? $t('CLINIC_SETTINGS.FORM.CPF.LABEL')
                  : $t('CLINIC_SETTINGS.FORM.CNPJ.LABEL')
              "
            >
              <div class="flex flex-col gap-2">
                <div class="inline-flex p-0.5 rounded-lg w-fit bg-n-slate-3">
                  <button
                    type="button"
                    class="px-3 py-1 text-sm font-medium rounded-md transition-colors"
                    :class="
                      docType === 'cnpj'
                        ? 'bg-n-slate-1 text-n-slate-12 shadow-sm'
                        : 'text-n-slate-11'
                    "
                    @click="setDocType('cnpj')"
                  >
                    {{ $t('CLINIC_SETTINGS.FORM.PJ') }}
                  </button>
                  <button
                    type="button"
                    class="px-3 py-1 text-sm font-medium rounded-md transition-colors"
                    :class="
                      docType === 'cpf'
                        ? 'bg-n-slate-1 text-n-slate-12 shadow-sm'
                        : 'text-n-slate-11'
                    "
                    @click="setDocType('cpf')"
                  >
                    {{ $t('CLINIC_SETTINGS.FORM.PF') }}
                  </button>
                </div>
                <NextInput
                  :model-value="form.cnpj"
                  type="text"
                  class="w-full"
                  :placeholder="
                    docType === 'cpf'
                      ? $t('CLINIC_SETTINGS.FORM.CPF.PLACEHOLDER')
                      : $t('CLINIC_SETTINGS.FORM.CNPJ.PLACEHOLDER')
                  "
                  @update:model-value="onCnpjInput"
                />
              </div>
            </WithLabel>

            <WithLabel :label="labelFor('phone')">
              <NextInput
                :model-value="form.phone"
                type="text"
                class="w-full"
                :placeholder="placeholderFor('phone')"
                @update:model-value="v => onFieldInput('phone', v)"
              />
            </WithLabel>

            <WithLabel :label="labelFor('website')">
              <NextInput
                v-model="form.website"
                type="text"
                class="w-full"
                :placeholder="placeholderFor('website')"
              />
            </WithLabel>
          </div>
        </SectionLayout>

        <SectionLayout
          :title="$t('CLINIC_SETTINGS.ADDRESS_SECTION.TITLE')"
          :description="$t('CLINIC_SETTINGS.ADDRESS_SECTION.NOTE')"
        >
          <div class="grid grid-cols-2 gap-4">
            <WithLabel
              v-for="key in ADDRESS_FIELDS"
              :key="key"
              :label="labelFor(key)"
              :class="
                ['address_street', 'address_complement'].includes(key)
                  ? 'col-span-2'
                  : ''
              "
            >
              <NextInput
                :model-value="form[key]"
                type="text"
                class="w-full"
                :placeholder="placeholderFor(key)"
                @update:model-value="v => onFieldInput(key, v)"
              />
            </WithLabel>
          </div>
        </SectionLayout>

        <div class="mt-2">
          <NextButton v-if="canManage" blue type="submit" :is-loading="saving">
            {{ $t('CLINIC_SETTINGS.SUBMIT') }}
          </NextButton>
        </div>
      </form>
    </div>
  </div>
</template>
