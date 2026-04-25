<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { waitingListStore } from '@plugins/agenda/frontend/features/waiting-list/store';

const props = defineProps({
  contact: {
    type: Object,
    default: () => ({}),
  },
  show: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

const selectedPeriod = ref('');
const selectedTime = ref('');
const selectedDays = ref([]);
const notes = ref('');
const isSubmitting = ref(false);
const isRemoving = ref(false);

const contactName = computed(() => props.contact?.name || '');
const contactPhone = computed(() => props.contact?.phone_number || '');

// Detecta se o contato já está na lista (por contact_id do banco)
const existingEntry = computed(() =>
  waitingListStore.entries.find(
    e => e.contact_id && e.contact_id === props.contact?.id
  )
);
const isEditing = computed(() => !!existingEntry.value);

const periods = [
  {
    value: 'morning',
    label: t('WAITING_LIST.PERIOD.MORNING'),
    icon: 'i-ph-sun-horizon',
    time: '06:00 – 12:00',
  },
  {
    value: 'afternoon',
    label: t('WAITING_LIST.PERIOD.AFTERNOON'),
    icon: 'i-ph-sun',
    time: '12:00 – 18:00',
  },
  {
    value: 'evening',
    label: t('WAITING_LIST.PERIOD.EVENING'),
    icon: 'i-ph-moon',
    time: '18:00 – 00:00',
  },
];

const weekdays = [
  { value: 'mon', label: 'SEG' },
  { value: 'tue', label: 'TER' },
  { value: 'wed', label: 'QUA' },
  { value: 'thu', label: 'QUI' },
  { value: 'fri', label: 'SEX' },
  { value: 'sat', label: 'SAB' },
  { value: 'sun', label: 'DOM' },
];

function toggleDay(day) {
  const idx = selectedDays.value.indexOf(day);
  if (idx === -1) selectedDays.value.push(day);
  else selectedDays.value.splice(idx, 1);
}

function close() {
  emit('close');
}

function loadFromEntry(entry) {
  selectedPeriod.value = entry.period || '';
  selectedTime.value = entry.specific_time || '';
  selectedDays.value = entry.preferred_days ? [...entry.preferred_days] : [];
  notes.value = entry.notes || '';
}

function resetForm() {
  selectedPeriod.value = '';
  selectedTime.value = '';
  selectedDays.value = [];
  notes.value = '';
  isSubmitting.value = false;
}

watch(
  () => props.show,
  newVal => {
    if (newVal) {
      if (existingEntry.value) loadFromEntry(existingEntry.value);
      else resetForm();
    }
  }
);

async function handleSubmit() {
  if (!selectedPeriod.value) {
    useAlert(t('WAITING_LIST.VALIDATION.PERIOD_REQUIRED'));
    return;
  }

  isSubmitting.value = true;

  try {
    await waitingListStore.save({
      contactId: props.contact?.id ?? null,
      period: selectedPeriod.value,
      specificTime: selectedTime.value || null,
      preferredDays: selectedDays.value,
      notes: notes.value,
    });

    const msg = isEditing.value
      ? t('WAITING_LIST.UPDATE_MESSAGE', { name: contactName.value })
      : t('WAITING_LIST.SUCCESS_MESSAGE', { name: contactName.value });
    useAlert(msg);
    close();
  } catch {
    useAlert(t('WAITING_LIST.ERROR_MESSAGE'));
  } finally {
    isSubmitting.value = false;
  }
}

async function handleRemove() {
  if (!existingEntry.value?.id) return;
  isRemoving.value = true;
  try {
    await waitingListStore.remove(existingEntry.value.id);
    useAlert(t('WAITING_LIST.REMOVE_MESSAGE', { name: contactName.value }));
    close();
  } catch {
    useAlert(t('WAITING_LIST.ERROR_MESSAGE'));
  } finally {
    isRemoving.value = false;
  }
}

function handleBackdropClick(event) {
  if (event.target === event.currentTarget) {
    close();
  }
}
</script>

<template>
  <Teleport to="body">
    <Transition name="wl-fade">
      <div v-if="show" class="wl-backdrop" @click="handleBackdropClick">
        <Transition name="wl-slide">
          <div
            v-if="show"
            class="wl-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="wl-title"
          >
            <!-- Header -->
            <div class="wl-header">
              <div class="wl-header-icon">
                <span class="i-ph-clock-countdown-duotone" />
              </div>
              <div class="wl-header-text">
                <h2 id="wl-title" class="wl-title">
                  {{ $t('WAITING_LIST.TITLE') }}
                </h2>
                <p class="wl-subtitle">
                  {{ $t('WAITING_LIST.SUBTITLE') }}
                </p>
              </div>
              <button
                class="wl-close-btn"
                :aria-label="$t('WAITING_LIST.CLOSE')"
                @click="close"
              >
                <span class="i-ph-x" />
              </button>
            </div>

            <!-- Banner: já está na lista -->
            <div v-if="isEditing" class="wl-already-banner">
              <span class="i-ph-clock-countdown wl-already-icon" />
              <span>{{ $t('WAITING_LIST.ALREADY_IN_LIST') }}</span>
            </div>

            <!-- Body -->
            <div class="wl-body">
              <!-- Contact info (minimal, read-only) -->
              <div class="wl-contact-card">
                <span class="wl-contact-initial">
                  {{ contactName.charAt(0).toUpperCase() }}
                </span>
                <div class="wl-contact-info">
                  <span class="wl-contact-name">{{ contactName }}</span>
                  <span v-if="contactPhone" class="wl-contact-phone">
                    {{ contactPhone }}
                  </span>
                </div>
                <span class="wl-contact-linked-badge">
                  {{ $t('WAITING_LIST.CONTACT_LINKED') }}
                </span>
              </div>

              <!-- Period selector -->
              <div class="wl-field-group">
                <label class="wl-label wl-label--required">
                  {{ $t('WAITING_LIST.PERIOD.LABEL') }}
                </label>
                <div class="wl-period-grid">
                  <button
                    v-for="period in periods"
                    :key="period.value"
                    type="button"
                    class="wl-period-btn"
                    :class="{
                      'wl-period-btn--active': selectedPeriod === period.value,
                    }"
                    @click="selectedPeriod = period.value"
                  >
                    <span class="wl-period-icon" :class="period.icon" />
                    <span class="wl-period-label">{{ period.label }}</span>
                    <span class="wl-period-time">{{ period.time }}</span>
                    <span
                      v-if="selectedPeriod === period.value"
                      class="i-ph-check wl-period-check"
                    />
                  </button>
                </div>
              </div>

              <!-- Preferred weekdays -->
              <div class="wl-field-group">
                <label class="wl-label">
                  {{ $t('WAITING_LIST.DAYS.LABEL') }}
                  <span class="wl-optional">
                    {{ $t('WAITING_LIST.OPTIONAL') }}
                  </span>
                </label>
                <div class="wl-days-grid">
                  <button
                    v-for="day in weekdays"
                    :key="day.value"
                    type="button"
                    class="wl-day-btn"
                    :class="{
                      'wl-day-btn--active': selectedDays.includes(day.value),
                    }"
                    @click="toggleDay(day.value)"
                  >
                    {{ day.label }}
                  </button>
                </div>
              </div>

              <!-- Specific time (optional) -->
              <div class="wl-field-group">
                <label class="wl-label" for="wl-time">
                  {{ $t('WAITING_LIST.TIME.LABEL') }}
                  <span class="wl-optional">
                    {{ $t('WAITING_LIST.OPTIONAL') }}
                  </span>
                </label>
                <input
                  id="wl-time"
                  v-model="selectedTime"
                  type="time"
                  class="wl-input wl-input--time"
                />
                <p class="wl-hint">
                  {{ $t('WAITING_LIST.TIME.HINT') }}
                </p>
              </div>

              <!-- Notes -->
              <div class="wl-field-group">
                <label class="wl-label" for="wl-notes">
                  {{ $t('WAITING_LIST.NOTES.LABEL') }}
                  <span class="wl-optional">
                    {{ $t('WAITING_LIST.OPTIONAL') }}
                  </span>
                </label>
                <textarea
                  id="wl-notes"
                  v-model="notes"
                  class="wl-textarea"
                  rows="3"
                  :placeholder="$t('WAITING_LIST.NOTES.PLACEHOLDER')"
                />
              </div>
            </div>

            <!-- Footer -->
            <div class="wl-footer">
              <!-- Remover (só quando já está na lista) -->
              <button
                v-if="isEditing"
                type="button"
                class="wl-btn wl-btn--danger wl-btn--icon-only"
                :disabled="isRemoving"
                :title="$t('WAITING_LIST.REMOVE')"
                @click="handleRemove"
              >
                <span v-if="isRemoving" class="i-ph-circle-notch wl-spinner" />
                <span v-else class="i-ph-trash" />
              </button>

              <div class="wl-footer-right">
                <button
                  type="button"
                  class="wl-btn wl-btn--secondary"
                  @click="close"
                >
                  {{ $t('WAITING_LIST.CANCEL') }}
                </button>
                <button
                  type="button"
                  class="wl-btn wl-btn--primary"
                  :disabled="isSubmitting || !selectedPeriod"
                  @click="handleSubmit"
                >
                  <span
                    v-if="isSubmitting"
                    class="i-ph-circle-notch wl-spinner"
                  />
                  <span v-else class="i-ph-clock-countdown" />
                  {{
                    isSubmitting
                      ? $t('WAITING_LIST.SUBMITTING')
                      : isEditing
                        ? $t('WAITING_LIST.UPDATE')
                        : $t('WAITING_LIST.SUBMIT')
                  }}
                </button>
              </div>
            </div>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
/* =============================================
   BACKDROP
   ============================================= */
.wl-backdrop {
  position: fixed;
  inset: 0;
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.6);
  backdrop-filter: blur(4px);
  padding: 16px;
}

/* =============================================
   MODAL CONTAINER
   ============================================= */
.wl-modal {
  width: 100%;
  max-width: 480px;
  border-radius: 16px;
  overflow: hidden;
  border: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-1));
  display: flex;
  flex-direction: column;
  max-height: 90vh;
}

/* =============================================
   HEADER
   ============================================= */
.wl-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 20px 20px 16px;
  border-bottom: 1px solid rgb(var(--slate-4));
}

.wl-header-icon {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: rgba(99, 102, 241, 0.12);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  color: #6366f1;
  font-size: 20px;
}

.wl-header-text {
  flex: 1;
  min-width: 0;
}

.wl-title {
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0;
  line-height: 1.3;
}

.wl-subtitle {
  font-size: 12px;
  color: rgb(var(--slate-9));
  margin: 2px 0 0;
}

.wl-close-btn {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  border: none;
  background: transparent;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgb(var(--slate-9));
  font-size: 16px;
  transition:
    background 0.15s,
    color 0.15s;
  flex-shrink: 0;
}

.wl-close-btn:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

/* =============================================
   BODY
   ============================================= */
.wl-body {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* =============================================
   BANNER: JÁ NA LISTA
   ============================================= */
.wl-already-banner {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 16px;
  background: rgba(99, 102, 241, 0.08);
  border-bottom: 1px solid rgba(99, 102, 241, 0.15);
  font-size: 12px;
  font-weight: 500;
  color: #6366f1;
}

.wl-already-icon {
  font-size: 14px;
  flex-shrink: 0;
}

/* =============================================
   WEEKDAY CHIPS
   ============================================= */
.wl-days-grid {
  display: flex;
  gap: 6px;
  flex-wrap: nowrap;
}

.wl-day-btn {
  flex: 1;
  min-width: 36px;
  height: 34px;
  border-radius: 8px;
  border: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-10));
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.3px;
  cursor: pointer;
  transition:
    background 0.12s,
    color 0.12s,
    border-color 0.12s;
}

.wl-day-btn:hover {
  background: rgb(var(--slate-3));
  border-color: rgb(var(--slate-6));
  color: rgb(var(--slate-12));
}

.wl-day-btn--active {
  background: rgba(99, 102, 241, 0.12);
  border-color: rgba(99, 102, 241, 0.4);
  color: #6366f1;
}

/* =============================================
   CONTACT CARD (mínimo)
   ============================================= */
.wl-contact-card {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
}

.wl-contact-initial {
  width: 26px;
  height: 26px;
  border-radius: 50%;
  background: rgba(99, 102, 241, 0.15);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  font-size: 11px;
  font-weight: 700;
  color: #6366f1;
}

.wl-contact-info {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: baseline;
  gap: 6px;
}

.wl-contact-name {
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.wl-contact-phone {
  font-size: 12px;
  color: rgb(var(--slate-9));
  white-space: nowrap;
}

.wl-contact-linked-badge {
  font-size: 10px;
  font-weight: 500;
  color: rgb(var(--slate-9));
  white-space: nowrap;
  flex-shrink: 0;
}

/* =============================================
   FIELD GROUP
   ============================================= */
.wl-field-group {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.wl-label {
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-11));
  display: flex;
  align-items: center;
  gap: 4px;
}

.wl-required {
  color: #dc2626;
  font-weight: 600;
}

.wl-label--required::after {
  content: '*';
  color: #dc2626;
  font-weight: 600;
  margin-left: 2px;
}

.wl-optional {
  font-size: 11px;
  font-weight: 400;
  color: rgb(var(--slate-9));
}

.wl-hint {
  font-size: 11px;
  color: rgb(var(--slate-9));
  margin: 0;
}

/* =============================================
   PERIOD SELECTOR
   ============================================= */
.wl-period-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
}

.wl-period-btn {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  padding: 14px 10px;
  border-radius: 12px;
  border: 1.5px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2));
  cursor: pointer;
  transition:
    border-color 0.15s,
    background 0.15s;
  box-shadow: none;
}

.wl-period-btn:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-3));
}

.wl-period-btn--active {
  border-color: #6366f1;
  background: rgba(99, 102, 241, 0.08);
}

.wl-period-icon {
  font-size: 22px;
  color: rgb(var(--slate-9));
}

.wl-period-btn--active .wl-period-icon {
  color: #6366f1;
}

.wl-period-label {
  font-size: 13px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.wl-period-time {
  font-size: 10px;
  color: rgb(var(--slate-9));
}

.wl-period-check {
  position: absolute;
  top: 6px;
  right: 6px;
  font-size: 14px;
  color: #6366f1;
}

/* =============================================
   TIME INPUT
   ============================================= */
.wl-input {
  width: 100%;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  color: rgb(var(--slate-12));
  font-size: 14px;
  outline: none;
  transition: border-color 0.15s;
  box-shadow: none;
}

.wl-input:focus {
  border-color: #6366f1;
  background: rgb(var(--slate-1));
  box-shadow: none;
}

.wl-input--time {
  padding: 10px 14px;
}

/* =============================================
   TEXTAREA
   ============================================= */
.wl-textarea {
  width: 100%;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  color: rgb(var(--slate-12));
  font-size: 14px;
  padding: 10px 14px;
  resize: vertical;
  min-height: 72px;
  outline: none;
  font-family: inherit;
  transition: border-color 0.15s;
  box-shadow: none;
}

.wl-textarea:focus {
  border-color: #6366f1;
  background: rgb(var(--slate-1));
  box-shadow: none;
}

.wl-textarea::placeholder {
  color: rgb(var(--slate-9));
}

/* =============================================
   FOOTER
   ============================================= */
.wl-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 16px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}

.wl-footer-right {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-left: auto;
}

.wl-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 16px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  border: none;
  transition:
    background 0.15s,
    opacity 0.15s;
  box-shadow: none;
  outline: none;
}

.wl-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.wl-btn--secondary {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
  border: 1px solid rgb(var(--slate-4));
}

.wl-btn--secondary:hover:not(:disabled) {
  background: rgb(var(--slate-4));
}

.wl-btn--primary {
  background: #6366f1;
  color: #fff;
}

.wl-btn--primary:hover:not(:disabled) {
  background: #4f46e5;
}

.wl-btn--danger {
  background: rgba(220, 38, 38, 0.08);
  color: #dc2626;
  border: 1px solid rgba(220, 38, 38, 0.2);
}

.wl-btn--danger:hover:not(:disabled) {
  background: rgba(220, 38, 38, 0.15);
  border-color: rgba(220, 38, 38, 0.35);
}

.wl-btn--icon-only {
  padding: 8px;
  width: 36px;
  height: 36px;
  justify-content: center;
}

.wl-btn--icon-only .i-ph-trash {
  font-size: 16px;
}

/* =============================================
   SPINNER
   ============================================= */
@keyframes wl-spin {
  from {
    transform: rotate(0deg);
  }

  to {
    transform: rotate(360deg);
  }
}

.wl-spinner {
  animation: wl-spin 0.8s linear infinite;
  font-size: 15px;
}

/* =============================================
   TRANSITIONS
   ============================================= */
.wl-fade-enter-active,
.wl-fade-leave-active {
  transition: opacity 0.2s ease;
}

.wl-fade-enter-from,
.wl-fade-leave-to {
  opacity: 0;
}

.wl-slide-enter-active,
.wl-slide-leave-active {
  transition:
    opacity 0.2s ease,
    transform 0.2s ease;
}

.wl-slide-enter-from,
.wl-slide-leave-to {
  opacity: 0;
  transform: translateY(16px) scale(0.97);
}
</style>
