<script setup>
import { computed, onMounted, ref } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import { format } from 'date-fns';
import { ptBR } from 'date-fns/locale';

import BillingMeter from './components/BillingMeter.vue';
import BillingCard from './components/BillingCard.vue';
import BillingHeader from './components/BillingHeader.vue';
import DetailItem from './components/DetailItem.vue';
import PurchaseCreditsModal from './components/PurchaseCreditsModal.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ButtonV4 from 'next/button/Button.vue';

const store = useStore();
const { accountId } = useAccount();
const {
  captainEnabled,
  captainLimits,
  documentLimits,
  responseLimits,
  fetchLimits,
  isFetchingLimits,
} = useCaptain();

const isLoading = ref(true);
const subscription = ref(null);
const error = ref(null);
const purchaseCreditsModalRef = ref(null);

const PLAN_LABELS = {
  standard: 'Standard',
  premium: 'Premium',
  enterprise: 'Enterprise',
};

const STATUS_LABELS = {
  trial: 'Trial',
  pending: 'Pagamento pendente',
  active: 'Ativa',
  overdue: 'Em atraso',
  canceled: 'Cancelada',
  lead: 'Lead Comercial',
};

const STATUS_COLORS = {
  trial: 'text-yellow-600 bg-yellow-50',
  pending: 'text-orange-600 bg-orange-50',
  active: 'text-green-600 bg-green-50',
  overdue: 'text-red-600 bg-red-50',
  canceled: 'text-slate-500 bg-slate-100',
  lead: 'text-blue-600 bg-blue-50',
};

const planLabel = computed(() =>
  subscription.value ? PLAN_LABELS[subscription.value.plan] || subscription.value.plan : '-'
);

const statusLabel = computed(() =>
  subscription.value ? STATUS_LABELS[subscription.value.status] || subscription.value.status : '-'
);

const statusColor = computed(() =>
  subscription.value ? STATUS_COLORS[subscription.value.status] || 'text-slate-600 bg-slate-100' : ''
);

const formattedPrice = computed(() => {
  if (!subscription.value?.price) return '-';
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    subscription.value.price
  );
});

const couponExpiresLabel = computed(() => {
  if (!subscription.value?.coupon_expires_at) return null;
  return format(new Date(subscription.value.coupon_expires_at), "dd 'de' MMMM 'de' yyyy", { locale: ptBR });
});

// Can purchase credits if plan is not free/hacker. In Klivy, anything with an active billing can.
const canPurchaseCredits = computed(() => {
  return true; 
});

const fetchSubscription = async () => {
  isLoading.value = true;
  error.value = null;
  try {
    const response = await window.axios.get(`/api/v1/billing/subscription`, {
      params: {
        account_id: accountId.value,
      },
    });
    subscription.value = response.data;
  } catch (e) {
    error.value = 'Não foi possível carregar os dados da assinatura.';
  } finally {
    isLoading.value = false;
  }
};

const onClickBillingPortal = () => {
  // If we have an Asaas implementation, we can redirect. For now, trigger original
  store.dispatch('accounts/checkout');
};

const onToggleChatWindow = () => {
  if (window.$chatwoot) window.$chatwoot.toggle();
};

const openPurchaseCreditsModal = () => {
  purchaseCreditsModalRef.value?.open();
};

const handleTopupSuccess = () => {
  fetchLimits();
};

const initialize = async () => {
  await fetchSubscription();
  fetchLimits();
};

onMounted(initialize);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="$t('ATTRIBUTES_MGMT.LOADING')"
    :no-records-found="!!error"
    :no-records-message="error || ''"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('BILLING_SETTINGS.TITLE')"
        :description="$t('BILLING_SETTINGS.DESCRIPTION')"
        feature-name="billing"
      />
    </template>
    <template #body>
      <section class="grid gap-4">
        <!-- Status do Plano (Klivy) -->
        <BillingCard
          :title="$t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.TITLE')"
          :description="$t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.DESCRIPTION')"
        >
          <div
            v-if="subscription"
            class="grid lg:grid-cols-4 sm:grid-cols-3 grid-cols-1 gap-2 divide-x divide-n-weak"
          >
            <DetailItem
              :label="$t('BILLING_SETTINGS.CURRENT_PLAN.TITLE')"
              :value="planLabel"
            />
            <DetailItem
              label="Status"
              :value="statusLabel"
            >
              <template #value>
                <span
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium"
                  :class="statusColor"
                >
                  {{ statusLabel }}
                </span>
              </template>
            </DetailItem>
            <DetailItem
              v-if="subscription.price"
              label="Mensalidade"
              :value="formattedPrice"
            />
            <DetailItem
              v-if="subscription.coupon_code"
              label="Cupom aplicado"
              :value="subscription.coupon_code"
            />
            <DetailItem
              v-if="couponExpiresLabel"
              label="Desconto válido até"
              :value="couponExpiresLabel"
            />
          </div>
        </BillingCard>

        <!-- Seção do Copilot (Captain) -->
        <BillingCard
          v-if="captainEnabled"
          :title="$t('BILLING_SETTINGS.CAPTAIN.TITLE')"
          :description="$t('BILLING_SETTINGS.CAPTAIN.DESCRIPTION')"
        >
          <template #action>
            <div class="flex gap-2">
              <ButtonV4
                sm
                flushed
                slate
                icon="i-lucide-refresh-cw"
                :is-loading="isFetchingLimits"
                @click="fetchLimits"
              >
                {{ $t('BILLING_SETTINGS.CAPTAIN.REFRESH_CREDITS') }}
              </ButtonV4>
              <ButtonV4
                v-if="canPurchaseCredits"
                sm
                solid
                blue
                @click="openPurchaseCreditsModal"
              >
                {{ $t('BILLING_SETTINGS.TOPUP.BUY_CREDITS') }}
              </ButtonV4>
            </div>
          </template>
          <div v-if="captainLimits && responseLimits" class="px-5">
            <BillingMeter
              :title="$t('BILLING_SETTINGS.CAPTAIN.RESPONSES')"
              v-bind="responseLimits"
            />
          </div>
          <div v-if="captainLimits && documentLimits" class="px-5">
            <BillingMeter
              :title="$t('BILLING_SETTINGS.CAPTAIN.DOCUMENTS')"
              v-bind="documentLimits"
            />
          </div>
        </BillingCard>
        <BillingCard
          v-else
          :title="$t('BILLING_SETTINGS.CAPTAIN.TITLE')"
          :description="$t('BILLING_SETTINGS.CAPTAIN.UPGRADE')"
        >
          <template #action>
            <ButtonV4 sm solid slate @click="onClickBillingPortal">
              {{ $t('CAPTAIN.PAYWALL.UPGRADE_NOW') }}
            </ButtonV4>
          </template>
        </BillingCard>

        <!-- Suporte -->
        <BillingHeader
          class="px-1 mt-5"
          :title="$t('BILLING_SETTINGS.CHAT_WITH_US.TITLE')"
          :description="$t('BILLING_SETTINGS.CHAT_WITH_US.DESCRIPTION')"
        >
          <ButtonV4
            sm
            solid
            slate
            icon="i-lucide-life-buoy"
            @click="onToggleChatWindow"
          >
            {{ $t('BILLING_SETTINGS.CHAT_WITH_US.BUTTON_TXT') }}
          </ButtonV4>
        </BillingHeader>
      </section>

      <PurchaseCreditsModal
        ref="purchaseCreditsModalRef"
        @success="handleTopupSuccess"
      />
    </template>
  </SettingsLayout>
</template>
