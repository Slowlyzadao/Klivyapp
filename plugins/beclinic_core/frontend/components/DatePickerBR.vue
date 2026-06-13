<script setup>
/**
 * DatePickerBR — Wrapper reutilizável de `vue-datepicker-next` com locale
 * pt-BR + estilo escuro do BeClinic. Substitui `<input type="date">` nativo
 * em todo o app, garantindo experiência consistente (formato DD/MM/YYYY,
 * popup estilizado, sem dependência do calendário do navegador).
 *
 * Comportamento:
 * - v-model emite/recebe string ISO 'YYYY-MM-DD' (compatível com APIs Rails).
 * - Display sempre em DD/MM/YYYY.
 * - Suporta date e datetime (props `type`).
 * - DOIS modos de entrada (default): digitar manualmente (parse via formato
 *   DD/MM/YYYY) OU escolher no calendário. Passe `:editable="false"` pra
 *   travar em só-calendário num caso específico.
 *
 * Uso:
 *   <DatePickerBR v-model="form.birthdate" />
 *   <DatePickerBR v-model="form.start" :max="today" placeholder="Início" />
 *   <DatePickerBR v-model="form.scheduled_at" type="datetime" />
 */
import { computed } from 'vue';
import DatePicker from 'vue-datepicker-next';
import 'vue-datepicker-next/index.css';

const props = defineProps({
  modelValue: { type: [String, Date, null], default: null },
  type: { type: String, default: 'date' }, // 'date' | 'datetime'
  placeholder: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  clearable: { type: Boolean, default: true },
  // Limites: aceita string ISO ('YYYY-MM-DD') ou Date.
  min: { type: [String, Date, null], default: null },
  max: { type: [String, Date, null], default: null },
  // Formato de exibição. Padrão BR; use 'DD/MM/YYYY HH:mm' para datetime.
  format: { type: String, default: '' },
  // Permite digitar a data manualmente (além do calendário). Default true —
  // a lib parseia o texto via `format`. `:editable="false"` trava só-calendário.
  editable: { type: Boolean, default: true },
});

const emit = defineEmits(['update:modelValue', 'change']);

const PT_BR_LANG = {
  formatLocale: {
    months: [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ],
    monthsShort: [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
    ],
    weekdays: [
      'Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira',
      'Quinta-feira', 'Sexta-feira', 'Sábado',
    ],
    weekdaysShort: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'],
    weekdaysMin: ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'],
    firstDayOfWeek: 0,
    firstWeekContainsDate: 1,
  },
  monthBeforeYear: false,
};

const computedFormat = computed(() => {
  if (props.format) return props.format;
  return props.type === 'datetime' ? 'DD/MM/YYYY HH:mm' : 'DD/MM/YYYY';
});

const valueType = computed(() =>
  props.type === 'datetime' ? 'YYYY-MM-DDTHH:mm:ss' : 'YYYY-MM-DD'
);

// Constrói disabledDate a partir dos limites min/max. Função recebe Date e
// retorna true se o dia deve ficar bloqueado.
const disabledDate = computed(() => {
  if (!props.min && !props.max) return null;
  const toDate = v => (v instanceof Date ? v : v ? new Date(v) : null);
  const minDate = toDate(props.min);
  const maxDate = toDate(props.max);
  if (minDate) minDate.setHours(0, 0, 0, 0);
  if (maxDate) maxDate.setHours(23, 59, 59, 999);
  return d => {
    if (minDate && d < minDate) return true;
    if (maxDate && d > maxDate) return true;
    return false;
  };
});

const onUpdate = val => {
  emit('update:modelValue', val ?? null);
  emit('change', val ?? null);
};
</script>

<template>
  <DatePicker
    :value="modelValue"
    :type="type"
    :value-type="valueType"
    :format="computedFormat"
    :lang="PT_BR_LANG"
    :placeholder="placeholder"
    :disabled="disabled"
    :clearable="clearable"
    :editable="editable"
    :disabled-date="disabledDate || undefined"
    :append-to-body="true"
    popup-class="bcdp-popup"
    class="bcdp"
    @update:value="onUpdate"
  />
</template>

<style scoped>
.bcdp {
  width: 100%;
}

/* Trigger (input visível) */
:deep(.mx-input) {
  background: rgb(var(--slate-2)) !important;
  border: 1px solid rgb(var(--slate-5)) !important;
  border-radius: 8px !important;
  height: 38px !important;
  color: rgb(var(--slate-12)) !important;
  font-size: 14px !important;
  font-weight: 500 !important;
  box-shadow: none !important;
  margin-bottom: 0 !important;
}

:deep(.mx-input:focus),
:deep(.mx-input:hover) {
  border-color: rgb(var(--blue-8)) !important;
  background: rgb(var(--slate-1)) !important;
}

:deep(.mx-input::placeholder) {
  color: rgb(var(--slate-8));
}

:deep(.mx-input:disabled) {
  background: rgb(var(--slate-3)) !important;
  cursor: not-allowed;
  opacity: 0.6;
}

:deep(.mx-icon-calendar),
:deep(.mx-icon-clear) {
  color: rgb(var(--slate-9)) !important;
  right: 10px;
}
</style>

<!-- Estilos globais do popup — vue-datepicker-next renderiza fora do escopo
     deste componente (append-to-body), por isso precisam ser non-scoped.
     z-index alto pra ficar acima dos modais do Chatwoot/woot-modal (~9999).
     Tanto .mx-datepicker-main quanto .mx-datepicker-popup são targetados
     porque a lib troca a classe quando appendToBody=true. -->
<style>
.mx-datepicker-popup,
.mx-datepicker-main,
.bcdp-popup {
  z-index: 100000 !important;
}

/* Popup (calendário) */
.mx-datepicker-main,
.mx-datepicker-popup {
  background-color: rgb(var(--slate-1)) !important;
  color: rgb(var(--slate-12)) !important;
  border: 1px solid rgb(var(--slate-5)) !important;
  border-radius: 12px !important;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2) !important;
  font-family: inherit;
}

/* Header do calendário (mês/ano + setas) */
.mx-datepicker-main .mx-calendar-header,
.mx-datepicker-popup .mx-calendar-header {
  color: rgb(var(--slate-12)) !important;
  border-bottom: 1px solid rgb(var(--slate-4)) !important;
}

.mx-datepicker-main .mx-calendar-header-label,
.mx-datepicker-popup .mx-calendar-header-label {
  color: rgb(var(--slate-12)) !important;
  font-weight: 700 !important;
}

.mx-datepicker-main .mx-btn,
.mx-datepicker-popup .mx-btn {
  color: rgb(var(--slate-12)) !important;
  font-weight: 600;
}

.mx-datepicker-main .mx-btn:hover,
.mx-datepicker-popup .mx-btn:hover {
  color: rgb(var(--blue-10)) !important;
  background: rgb(var(--slate-3)) !important;
}

.mx-datepicker-main .mx-icon-double-left,
.mx-datepicker-main .mx-icon-double-right,
.mx-datepicker-main .mx-icon-left,
.mx-datepicker-main .mx-icon-right,
.mx-datepicker-popup .mx-icon-double-left,
.mx-datepicker-popup .mx-icon-double-right,
.mx-datepicker-popup .mx-icon-left,
.mx-datepicker-popup .mx-icon-right {
  color: rgb(var(--slate-11)) !important;
}

/* Dias da semana (D S T Q Q S S) */
.mx-datepicker-main .mx-table th,
.mx-datepicker-popup .mx-table th {
  color: rgb(var(--slate-10)) !important;
  font-weight: 600 !important;
  text-transform: uppercase;
  font-size: 11px;
}

/* Células dos dias — alta especificidade pra vencer o estilo default */
.mx-datepicker-main .mx-table .cell,
.mx-datepicker-main td.cell,
.mx-datepicker-popup .mx-table .cell,
.mx-datepicker-popup td.cell {
  color: rgb(var(--slate-12)) !important;
  font-weight: 500 !important;
  background: transparent !important;
}

.mx-datepicker-main .mx-table .cell:hover,
.mx-datepicker-main td.cell:hover,
.mx-datepicker-popup .mx-table .cell:hover,
.mx-datepicker-popup td.cell:hover {
  background-color: rgb(var(--slate-3)) !important;
  color: rgb(var(--slate-12)) !important;
  border-radius: 6px;
}

.mx-datepicker-main .mx-table .cell.today,
.mx-datepicker-main td.cell.today,
.mx-datepicker-popup .mx-table .cell.today,
.mx-datepicker-popup td.cell.today {
  color: rgb(var(--blue-10)) !important;
  font-weight: 700 !important;
}

.mx-datepicker-main .mx-table .cell.active,
.mx-datepicker-main td.cell.active,
.mx-datepicker-popup .mx-table .cell.active,
.mx-datepicker-popup td.cell.active {
  background-color: rgb(var(--blue-9)) !important;
  color: #fff !important;
  font-weight: 700 !important;
  border-radius: 6px;
}

.mx-datepicker-main .mx-table .cell.not-current-month,
.mx-datepicker-main td.cell.not-current-month,
.mx-datepicker-popup .mx-table .cell.not-current-month,
.mx-datepicker-popup td.cell.not-current-month {
  color: rgb(var(--slate-8)) !important;
  font-weight: normal !important;
}

.mx-datepicker-main .mx-table .cell.disabled,
.mx-datepicker-main td.cell.disabled,
.mx-datepicker-popup .mx-table .cell.disabled,
.mx-datepicker-popup td.cell.disabled {
  color: rgb(var(--slate-7)) !important;
  background: transparent !important;
  cursor: not-allowed;
  text-decoration: line-through;
}

/* Sidebar de "atalhos" (Hoje, Ontem, etc) — caso a lib mostre */
.mx-datepicker-main .mx-datepicker-sidebar,
.mx-datepicker-popup .mx-datepicker-sidebar {
  border-right: 1px solid rgb(var(--slate-4)) !important;
}

.mx-datepicker-main .mx-datepicker-btn-confirm,
.mx-datepicker-popup .mx-datepicker-btn-confirm {
  background: rgb(var(--blue-9)) !important;
  color: #fff !important;
  border-radius: 6px;
}
</style>
