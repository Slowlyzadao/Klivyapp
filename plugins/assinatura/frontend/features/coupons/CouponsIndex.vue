<script setup>
import { ref, onMounted } from 'vue';
import { useCoupons } from './composables/useCoupons.js';
import { useCouponForm } from './composables/useCouponForm.js';
import CouponCard from './components/CouponCard.vue';
import CouponFormModal from './components/CouponFormModal.vue';
import AsIcon from '../../shared/AsIcon.vue';
import '../../shared/assinatura.css';
import './coupons.css';

const showModal = ref(false);
const toast = ref(null);

const { coupons, loading, error, fetchCoupons, deleteCoupon, upsertCoupon } = useCoupons();

const { form, editingId, saving, formError, openNew, openEdit, generateCode, save } =
  useCouponForm(coupon => {
    upsertCoupon(coupon);
    showModal.value = false;
    showToast('Cupom salvo com sucesso!');
  });

function handleNew() {
  openNew();
  showModal.value = true;
}

function handleEdit(coupon) {
  openEdit(coupon);
  showModal.value = true;
}

async function handleDelete(coupon) {
  if (!window.confirm(`Excluir o cupom "${coupon.code}"? Esta ação não pode ser desfeita.`)) return;
  try {
    await deleteCoupon(coupon.id);
    showToast('Cupom excluído.');
  } catch (e) {
    showToast('Erro ao excluir cupom.', true);
  }
}

function showToast(msg, isError = false) {
  toast.value = { msg, isError };
  setTimeout(() => (toast.value = null), 3500);
}

onMounted(fetchCoupons);
</script>

<template>
  <div class="as-page">
    <header class="as-page__header">
      <div>
        <h1 class="as-page__title">Cupons de Desconto</h1>
        <p class="as-page__subtitle">Gerencie os cupons de trial, desconto e acesso gratuito</p>
      </div>
      <button type="button" class="reset-base as-btn as-btn--primary" @click="handleNew">
        <AsIcon name="add" :size="16" />
        Novo Cupom
      </button>
    </header>

    <div v-if="loading" class="as-loading">
      <AsIcon name="loader" :size="20" class="as-spin" />
      <span>Carregando cupons...</span>
    </div>

    <div v-else-if="error" class="as-alert as-alert--error" style="margin: 1.5rem">{{ error }}</div>

    <div v-else-if="coupons.length === 0" class="as-empty">
      <AsIcon name="ticket" :size="48" class="as-empty__icon" />
      <p class="as-empty__text">Nenhum cupom cadastrado ainda.</p>
      <button type="button" class="reset-base as-btn as-btn--primary" @click="handleNew">Criar primeiro cupom</button>
    </div>

    <div v-else class="coupons-list">
      <div class="coupons-header-row">
        <span>Código</span>
        <span>Tipo / Benefício</span>
        <span>Uso / Validade</span>
        <span />
      </div>
      <CouponCard
        v-for="coupon in coupons"
        :key="coupon.id"
        :coupon="coupon"
        @edit="handleEdit"
        @delete="handleDelete"
      />
    </div>

    <CouponFormModal
      v-if="showModal"
      :form="form"
      :editing-id="editingId"
      :saving="saving"
      :error="formError"
      @save="save"
      @close="showModal = false"
      @generate-code="generateCode"
    />

    <div v-if="toast" class="as-toast" :class="{ 'as-toast--error': toast.isError }">
      <AsIcon :name="toast.isError ? 'alert' : 'check'" :size="16" />
      {{ toast.msg }}
    </div>
  </div>
</template>
