<template>

    <div class="tab-content" @click="openDropdownIndex = null; dropdownPos = null;">
      <!-- Dropdown flutuante (Exceções) -->
      <teleport to="body">
        <div
          v-if="
            openDropdownIndex !== null &&
            typeof openDropdownIndex === 'number' &&
            dropdownPos
          "
          class="exc-dropdown-floating"
          :style="{
            top: dropdownPos.top + 'px',
            left: dropdownPos.left + 'px',
            width: dropdownPos.width + 'px',
          }"
          @click.stop
        >
          <div
            v-for="(cat, ci) in exceptionCategories"
            :key="ci"
            class="exc-dropdown-item"
            :class="{
              active:
                exceptions[openDropdownIndex] &&
                exceptions[openDropdownIndex].type === cat,
            }"
            @click="selectCategory(exceptions[openDropdownIndex], cat)"
          >
            <i
              class="i-lucide-check size-[13px]"
              :style="{
                opacity:
                  exceptions[openDropdownIndex] &&
                  exceptions[openDropdownIndex].type === cat
                    ? 1
                    : 0,
              }"
            />
            <span>{{ cat }}</span>
          </div>
        </div>
      </teleport>

      <!-- ────── ESQUERDA ────── -->
      <div class="col-left">
        <!-- Horários de funcionamento -->
        <section class="schedule-section">
          <div class="flex-row-center justify-between mb-4">
            <h2 class="section-title mb-0">Horários de funcionamento</h2>
          </div>

          <div class="schedule-list">
            <!-- Rows -->
            <div
              v-for="(day, index) in weekDays"
              :key="day.id"
              class="schedule-card"
              :class="{
                'card-disabled': !day.enabled,
                'card-last': index === weekDays.length - 1,
              }"
            >
              <!-- Lado Esquerdo: Toggle + Nome do Dia -->
              <div class="day-info">
                <button
                  class="toggle-switch toggle-compact"
                  :class="{ 'toggle-on': day.enabled }"
                  @click="day.enabled = !day.enabled"
                >
                  <span class="toggle-thumb" />
                </button>
                <span
                  class="day-label"
                  :class="day.enabled ? 'text-active' : 'text-muted'"
                >
                  {{ day.label }}
                </span>
              </div>

              <!-- Centro: Horários de Atendimento e Almoço -->
              <div class="day-settings">
                <!-- Expediente -->
                <div class="setting-group" :class="{ disabled: !day.enabled }">
                  <span class="setting-label">Atendimento</span>
                  <div class="time-inputs-wrap">
                    <div class="time-field-compact">
                      <input
                        v-model="day.start"
                        type="time"
                        class="time-inp"
                        :disabled="!day.enabled"
                      />
                    </div>
                    <span class="time-sep">até</span>
                    <div class="time-field-compact">
                      <input
                        v-model="day.end"
                        type="time"
                        class="time-inp"
                        :disabled="!day.enabled"
                      />
                    </div>
                  </div>
                </div>

                <!-- Intervalo -->
                <div class="setting-group" :class="{ disabled: !day.enabled }">
                  <span class="setting-label">Almoço</span>
                  <div class="time-inputs-wrap">
                    <div class="time-field-compact">
                      <input
                        v-model="day.lunchStart"
                        type="time"
                        class="time-inp"
                        :disabled="!day.enabled"
                      />
                    </div>
                    <span class="time-sep">até</span>
                    <div class="time-field-compact">
                      <input
                        v-model="day.lunchEnd"
                        type="time"
                        class="time-inp"
                        :disabled="!day.enabled"
                      />
                    </div>
                  </div>
                </div>
              </div>

              <!-- Lado Direito: Status -->
              <div class="day-status">
                <span
                  class="status-badge-modern"
                  :class="getDayStatus(day).cls"
                >
                  {{ getDayStatus(day).label }}
                </span>
              </div>
            </div>
          </div>
        </section>

        <!-- Exceções e Folgas -->
        <section class="exceptions-section">
          <div class="flex items-center justify-between mb-4">
            <h2 class="section-title mb-0">Exceções e Folgas</h2>
            <button class="add-exception-btn" @click="addException">
              <i class="i-lucide-plus size-4" />
              <span>Adicionar</span>
            </button>
          </div>

          <div v-if="exceptions.length === 0" class="exceptions-empty">
            <i class="i-lucide-calendar-off size-8 opacity-20 mb-3" />
            <p>Nenhuma exceção ou folga registrada.</p>
          </div>

          <div class="exceptions-list-modern">
            <div
              v-for="(ex, index) in exceptions"
              :key="index"
              class="exception-row-card"
            >
              <!-- Info e Ações -->
              <div class="exc-row-header">
                <div class="exc-row-info">
                  <div
                    class="exc-row-icon"
                    :class="`bg-${getExceptionMeta(ex.type).color}-500/10 text-${getExceptionMeta(ex.type).color}-400`"
                  >
                    <i :class="getExceptionMeta(ex.type).icon" class="size-4" />
                  </div>
                  <div class="exc-row-title-wrap">
                    <input
                      v-model="ex.title"
                      type="text"
                      class="exc-row-input-title"
                      placeholder="Nome do evento"
                    />
                  </div>
                </div>
                <button
                  class="exc-row-delete"
                  title="Remover"
                  @click.stop="removeException(index)"
                >
                  <i class="i-lucide-trash-2 size-4" />
                </button>
              </div>

              <!-- Controles -->
              <div class="exc-row-body">
                <div class="exc-row-dates">
                  <div class="exc-row-field">
                    <span class="exc-row-label">Início</span>
                    <DatePicker
                      v-model:value="ex.start"
                      type="date"
                      value-type="YYYY-MM-DD"
                      format="DD/MM/YYYY"
                      :lang="ptBrLang"
                      :clearable="false"
                      :editable="false"
                      class="clean-datepicker"
                    />
                  </div>
                  <div class="exc-row-field">
                    <span class="exc-row-label">Fim</span>
                    <DatePicker
                      v-model:value="ex.end"
                      type="date"
                      value-type="YYYY-MM-DD"
                      format="DD/MM/YYYY"
                      :lang="ptBrLang"
                      :clearable="false"
                      :editable="false"
                      class="clean-datepicker"
                    />
                  </div>
                </div>

                <div class="exc-row-field flex-1">
                  <span class="exc-row-label">Categoria</span>
                  <div
                    class="exc-row-select"
                    :class="{ active: openDropdownIndex === index }"
                    @click.stop="toggleDropdown(index, $event)"
                  >
                    <i class="i-lucide-tag size-3.5 opacity-50" />
                    <span class="flex-1 truncate">{{ ex.type }}</span>
                    <i class="i-lucide-chevron-down size-3.5 opacity-50" />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>

      <!-- ────── DIREITA: Configurações Globais ────── -->
      <div class="col-right">
        <!-- Header de Ações -->
        <div class="flex items-center justify-between">
          <h2 class="section-title mb-0">Configurações</h2>
          <button
            class="save-btn-premium"
            :class="{ saving: saving }"
            @click="saveChanges"
          >
            <i v-if="saving" class="i-lucide-loader-2 animate-spin size-4" />
            <i v-else class="i-lucide-check-circle size-4" />
            <span>{{ saving ? 'Salvando' : 'Salvar' }}</span>
          </button>
        </div>

        <!-- ════ REGRAS DE DISPONIBILIDADE ════ -->
        <div class="availability-rules-compact">
          <span class="rules-group-label">Regras de agendamento</span>
          <div class="rule-row-modern mt-2">
            <div class="rule-icon-sq bg-blue-500/10 text-blue-400">
              <i class="i-lucide-calendar-clock size-4" />
            </div>

            <div class="rule-info-main">
              <span class="rule-label-main">Respeitar expediente</span>
              <span class="rule-sub-main">Bloquear fora do horário</span>
            </div>
            <button
              class="toggle-switch toggle-compact"
              :class="{ 'toggle-on': blockOutsideWorkingHours }"
              @click="$emit('update:blockOutsideWorkingHours', !blockOutsideWorkingHours)"
            >
              <span class="toggle-thumb" />
            </button>
          </div>

          <div class="rule-row-modern mt-3">
            <div class="rule-icon-sq bg-orange-500/10 text-orange-400">
              <i class="i-lucide-utensils size-4" />
            </div>
            <div class="rule-info-main">
              <span class="rule-label-main">Bloquear almoço</span>
              <span class="rule-sub-main">Respeitar intervalos</span>
            </div>
            <button
              class="toggle-switch toggle-compact"
              :class="{ 'toggle-on toggle-orange': blockLunchBreak }"
              @click="$emit('update:blockLunchBreak', !blockLunchBreak)"
            >
              <span class="toggle-thumb" />
            </button>
          </div>

          <div class="rule-row-modern mt-3">
            <div class="rule-icon-sq bg-rose-500/10 text-rose-400">
              <i class="i-lucide-history size-4" />
            </div>
            <div class="rule-info-main">
              <span class="rule-label-main">Bloquear datas passadas</span>
              <span class="rule-sub-main">Impedir agendamentos no passado</span>
            </div>
            <button
              class="toggle-switch toggle-compact"
              :class="{ 'toggle-on toggle-rose': blockPastDates }"
              @click="$emit('update:blockPastDates', !blockPastDates)"
            >
              <span class="toggle-thumb" />
            </button>
          </div>

          <div class="rule-row-modern mt-3">
            <div class="rule-icon-sq bg-emerald-500/10 text-emerald-400">
              <i class="i-lucide-eye size-4" />
            </div>
            <div class="rule-info-main">
              <span class="rule-label-main">Mostrar apenas horários disponíveis</span>
              <span class="rule-sub-main">Esconder horas fora do expediente no calendário</span>
            </div>
            <button
              class="toggle-switch toggle-compact"
              :class="{ 'toggle-on toggle-emerald': showOnlyWorkingHours }"
              @click="$emit('update:showOnlyWorkingHours', !showOnlyWorkingHours)"
            >
              <span class="toggle-thumb" />
            </button>
          </div>

          <div v-if="showOnlyWorkingHours" class="rule-row-modern mt-3">
            <div class="rule-icon-sq bg-emerald-500/10 text-emerald-400">
              <i class="i-lucide-clock-arrow-up size-4" />
            </div>
            <div class="rule-info-main">
              <span class="rule-label-main">Margem visível antes/depois</span>
              <span class="rule-sub-main">Horas extras na grade (apenas visual)</span>
            </div>
            <div class="buffer-stepper">
              <button
                type="button"
                class="buffer-stepper-btn"
                :disabled="visibleHoursBuffer <= 0"
                @click="onBufferStep(-1)"
              >
                <i class="i-lucide-minus size-3.5" />
              </button>
              <span class="buffer-stepper-value">{{ visibleHoursBuffer }}h</span>
              <button
                type="button"
                class="buffer-stepper-btn"
                :disabled="visibleHoursBuffer >= 6"
                @click="onBufferStep(1)"
              >
                <i class="i-lucide-plus size-3.5" />
              </button>
            </div>
          </div>
        </div>

        <!-- ════ FERIADOS (MINIMALISTA) ════ -->
        <div class="holidays-section-modern">
          <span class="rules-group-label mb-3 block">Feriados Nacionais</span>
          <div class="holidays-list-clean">
            <div
              v-for="(hol, index) in holidays"
              :key="index"
              class="holiday-item-clean"
              @click="toggleHolidayStatus(hol)"
            >
              <div class="hol-indicator" :class="hol.status" />
              <div class="hol-content-main">
                <span class="hol-name-text">{{ hol.name }}</span>
                <span class="hol-date-text">{{ hol.date }}</span>
              </div>
              <div class="hol-status-tag" :class="hol.status">
                {{ hol.status === 'closed' ? 'Fechado' : 'Aberto' }}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    </template>

<script setup>
import { defineProps, defineEmits, onMounted, onUnmounted } from 'vue';
import { useSettingsSchedules } from '../composables/useSettingsSchedules';
import DatePicker from 'vue-datepicker-next';
import 'vue-datepicker-next/index.css';

const props = defineProps({
  weekDays: Array,
  exceptions: Array,
  holidays: Array,
  blockOutsideWorkingHours: Boolean,
  blockLunchBreak: Boolean,
  blockPastDates: Boolean,
  showOnlyWorkingHours: Boolean,
  visibleHoursBuffer: { type: Number, default: 2 },
  saving: Boolean
});

const emit = defineEmits([
  'update:blockOutsideWorkingHours',
  'update:blockLunchBreak',
  'update:blockPastDates',
  'update:showOnlyWorkingHours',
  'update:visibleHoursBuffer',
  'add-exception',
  'remove-exception',
  'save-changes'
]);

const onBufferStep = (delta) => {
  const next = Math.max(0, Math.min(6, (props.visibleHoursBuffer || 0) + delta));
  if (next !== props.visibleHoursBuffer) emit('update:visibleHoursBuffer', next);
};

const {
  getDayStatus,
  getExceptionMeta,
  exceptionCategories,
  openDropdownIndex,
  dropdownPos,
  toggleDropdown,
  selectCategory,
  ptBrLang,
  toggleHolidayStatus,
  addException,
  removeException,
  saveChanges
} = useSettingsSchedules(props, emit);

const handleClickOutside = (e) => {
  if (!e.target.closest('.exc-row-select')) {
    openDropdownIndex.value = null;
    dropdownPos.value = null;
  }
};
onMounted(() => document.addEventListener('click', handleClickOutside));
onUnmounted(() => document.removeEventListener('click', handleClickOutside));
</script>

<style scoped>
/* ───────── SCHEDULE LIST (MODERN) ───────── */
.schedule-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.schedule-card {
  display: grid;
  grid-template-columns: 1fr auto;
  grid-template-areas:
    "info status"
    "settings settings";
  gap: 16px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 16px 20px;
  transition: all 0.2s ease;
}
@media (min-width: 1024px) {
  .schedule-card {
    grid-template-columns: 180px 1fr 100px;
    grid-template-areas: "info settings status";
    align-items: center;
    gap: 20px;
    padding: 12px 20px;
  }
}

.schedule-card:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-3));
}

.schedule-card.card-disabled {
  opacity: 0.55;
  background: rgba(var(--slate-2), 0.5);
}

/* Lado esquerdo */
.day-info {
  grid-area: info;
  display: flex;
  align-items: center;
  justify-content: flex-start;
  gap: 12px;
}

.toggle-switch {
  position: relative;
  width: 44px;
  height: 24px;
  background: rgb(var(--slate-6));
  border-radius: 12px;
  border: none;
  cursor: pointer;
  transition: background 0.2s;
  flex-shrink: 0;
  padding: 0 !important;
  box-sizing: border-box !important;
}
.toggle-switch.toggle-on {
  background: rgb(var(--blue-9));
}
.toggle-thumb {
  position: absolute;
  top: 3px;
  left: 3px;
  width: 18px;
  height: 18px;
  background: #fff;
  border-radius: 50%;
  transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
  padding: 0 !important;
  margin: 0 !important;
  box-sizing: border-box !important;
}
.toggle-switch.toggle-on .toggle-thumb {
  transform: translateX(20px);
}

.toggle-compact {
  width: 38px !important;
  height: 20px !important;
}
.toggle-compact .toggle-thumb {
  width: 14px !important;
  height: 14px !important;
  top: 3px !important;
  left: 3px !important;
}
.toggle-compact.toggle-on .toggle-thumb {
  left: calc(100% - 17px) !important;
  transform: none !important;
}


/* Centro: Agrupamento de inputs */
.day-settings {
  grid-area: settings;
  display: flex;
  flex-direction: column;
  gap: 16px;
  width: 100%;
}
@media (min-width: 768px) {
  .day-settings {
    flex-direction: row;
    align-items: center;
    gap: 40px;
    width: auto;
  }
}

.setting-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
  width: 100%;
}
@media (min-width: 768px) {
  .setting-group {
    width: auto;
  }
}

.setting-label {
  @apply text-sm;
  font-weight: 700;
  text-transform: uppercase;
  color: rgb(var(--slate-8));
  letter-spacing: 0.05em;
}

.time-inputs-wrap {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  width: 100%;
}
@media (min-width: 768px) {
  .time-inputs-wrap {
    width: auto;
    justify-content: flex-start;
  }
}

.time-sep {
  @apply text-sm;
  color: rgb(var(--slate-7));
  font-weight: 500;
}

.time-field-compact {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  padding: 0px 8px;
  height: 36px;
  display: flex;
  align-items: center;
  flex: 1;
  transition: border-color 0.15s;
}
@media (min-width: 768px) {
  .time-field-compact {
    flex: none;
  }
}

.time-field-compact:focus-within {
  border-color: rgb(var(--blue-8));
  background: rgb(var(--slate-1));
}

.time-field-compact .time-inp {
  background: transparent;
  border: none;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 600;
  width: 100%;
  min-width: 50px;
  padding: 0;
  outline: none;
}
@media (min-width: 768px) {
  .time-field-compact .time-inp {
    width: 75px;
  }
}

/* Status Badge Modern */
.day-status {
  grid-area: status;
  display: flex;
  align-items: center;
  justify-content: flex-end;
}
.status-badge-modern {
  @apply text-sm;
  font-weight: 700;
  padding: 3px 10px;
  border-radius: 6px;
}

.status-badge-modern.open {
  color: #10b981;
}
.status-badge-modern.closed {
  color: #ef4444;
}

/* ───────── UTILITIES ───────── */
.flex-row-center {
  display: flex;
  align-items: center;
}
.justify-between {
  justify-content: space-between;
}
.gap-2 {
  gap: 8px;
}
.mb-4 {
  margin-bottom: 16px;
}
.mb-0 {
  margin-bottom: 0;
}
.mb-5 {
  margin-bottom: 20px;
}
.text-active {
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 500;
}
.text-muted {
  color: rgb(var(--slate-9));
  @apply text-sm;
  font-weight: 500;
}
.day-label {
  white-space: nowrap;
}

/* ───────── CHECKBOX ───────── */
.theme-checkbox {
  appearance: none;
  width: 15px;
  height: 15px;
  border-radius: 4px;
  border: 1px solid rgb(var(--slate-6));
  background: transparent;
  cursor: pointer;
  position: relative;
  transition: all 0.15s;
  flex-shrink: 0;
}
.theme-checkbox:checked {
  background: rgb(var(--blue-9));
  border-color: rgb(var(--blue-9));
}
.theme-checkbox:checked::after {
  content: '';
  position: absolute;
  top: 1px;
  left: 4px;
  width: 4px;
  height: 8px;
  border: solid white;
  border-width: 0 2px 2px 0;
  transform: rotate(45deg);
}

/* ───────── TIME FIELD ───────── */
.time-field {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  padding: 4px 8px;
  transition: border-color 0.15s;
}
.time-field:focus-within {
  border-color: rgb(var(--blue-9));
  background: rgb(var(--slate-1));
}
.time-field.time-disabled {
  opacity: 0.45;
}
.time-ico {
  width: 12px;
  height: 12px;
  color: rgb(var(--slate-8));
  flex-shrink: 0;
}
/* Limpeza brutal para evitar dupla borda nativa do navegador */
.time-inp {
  width: 52px;
  background: transparent !important;
  border: none !important;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 500;
  text-align: center;
  outline: none !important;
  box-shadow: none !important;
  cursor: pointer;
  padding: 0 !important;
  margin: 0 !important;
}
.time-inp:disabled {
  color: rgb(var(--slate-8));
  cursor: not-allowed;
}
.time-inp::-webkit-calendar-picker-indicator {
  display: none !important;
  -webkit-appearance: none !important;
}

/* ───────── STATUS BADGE ───────── */
.status-badge {
  @apply text-sm font-semibold px-2.5 py-1 rounded-md whitespace-nowrap;
}
.status-badge.open {
  background-color: #dcfce7;
  color: #166534;
  box-shadow: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
  border: 1px solid #bbf7d0;
}
.status-badge.closed {
  background-color: #fee2e2;
  color: #991b1b;
  box-shadow: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
  border: 1px solid #fecaca;
}

/* ───────── LINK BTN ───────── */
.link-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--blue-9));
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 0;
  transition: color 0.15s;
}
.link-btn:hover {
  color: rgb(var(--blue-10));
}

/* ───────── EXCEPTIONS (MODERN LIST) ───────── */
.add-exception-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background: rgba(var(--blue-9), 0.1);
  color: rgb(var(--blue-9));
  border: 1px solid rgba(var(--blue-9), 0.2);
  border-radius: 8px;
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}
.add-exception-btn:hover {
  background: rgba(var(--blue-9), 0.15);
  border-color: rgba(var(--blue-9), 0.4);
}

.exceptions-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 40px;
  background: rgba(var(--slate-2), 0.5);
  border: 1px dashed rgb(var(--slate-4));
  border-radius: 12px;
  color: rgb(var(--slate-8));
  @apply text-sm;
}

.exceptions-list-modern {
  display: grid;
  grid-template-columns: 1fr;
  gap: 12px;
}
@media (min-width: 768px) {
  .exceptions-list-modern {
    grid-template-columns: repeat(2, 1fr);
  }
}

.exception-row-card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 14px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  transition: all 0.2s;
}
.exception-row-card:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-3));
}

.exc-row-header {
  display: flex;
  align-items: center; /* Garante centralização vertical total */
  justify-content: space-between;
  gap: 12px;
  min-height: 32px; /* Altura fixa para manter estabilidade */
}

.exc-row-info {
  display: flex;
  align-items: center; /* Alinha ícone e título perfeitamente */
  gap: 12px;
  flex: 1;
  min-width: 0;
}

.exc-row-icon {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  line-height: 0; /* Evita deslocamento por line-height */
}

.exc-row-title-wrap {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center; /* Centraliza o input internamente */
}

.exc-row-input-title {
  width: 100%;
  background: transparent;
  border: none;
  @apply text-sm;
  font-weight: 700;
  color: rgb(var(--slate-12));
  padding: 0;
  margin: 0 !important; /* Força margin zero para anular globais */
  margin-bottom: 0 !important;
  outline: none;
  height: 32px;
  line-height: normal;
  display: flex;
  align-items: center;
}
.exc-row-input-title:focus {
  border-bottom: 1px solid rgb(var(--blue-9));
}

.exc-row-delete {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgb(var(--slate-7));
  border-radius: 8px;
  background: transparent;
  border: none;
  padding: 0;
  cursor: pointer;
  transition: all 0.15s;
}
.exc-row-delete:hover {
  background: rgba(239, 68, 68, 0.1);
  color: #dc2626;
}

.exc-row-body {
  display: flex;
  gap: 12px;
  padding-top: 4px;
}

.exc-row-dates {
  display: flex;
  gap: 8px;
  flex: 1.5;
}

.exc-row-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
}

.exc-row-label {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  color: rgb(var(--slate-8));
  letter-spacing: 0.04em;
}

.exc-row-select {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 6px 10px;
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  height: 34px;
  transition:
    border-color 0.15s,
    background 0.15s;
}
.exc-row-select:hover {
  background: rgb(var(--slate-3));
  border-color: rgb(var(--slate-6));
}
.exc-row-select.active {
  border-color: rgb(var(--blue-8));
  background: rgb(var(--slate-1));
}
.exc-row-select span {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-11));
}

:deep(.clean-datepicker) {
  width: 100%;
}
:deep(.clean-datepicker .mx-input) {
  background: rgb(var(--slate-2)) !important;
  border: 1px solid rgb(var(--slate-5)) !important;
  border-radius: 8px !important;
  height: 34px !important;
  color: rgb(var(--slate-12)) !important;
  font-size: 12px !important;
  font-weight: 600 !important;
  box-shadow: none !important;
  margin-bottom: 0 !important;
}
:deep(.clean-datepicker .mx-input:focus) {
  border-color: rgb(var(--blue-8)) !important;
  background: rgb(var(--slate-1)) !important;
}
:deep(.clean-datepicker .mx-icon-calendar) {
  display: none !important;
}

/* Estilização Premium do Calendário Pop-up */
:deep(.mx-datepicker-main) {
  background-color: rgb(var(--slate-2)) !important;
  color: rgb(var(--slate-12)) !important;
  border: 1px solid rgb(var(--slate-5)) !important;
  border-radius: 12px !important;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2) !important;
}

:deep(.mx-calendar-content .cell.active) {
  background-color: rgb(var(--blue-9)) !important;
  color: #fff !important;
}

/* Dias do mês atual */
:deep(.mx-calendar-content .cell) {
  color: rgb(var(--slate-12)) !important;
  font-weight: 500 !important;
}

/* Dias de outros meses em cinza */
:deep(.mx-calendar-content .cell.not-current-month) {
  color: rgb(var(--slate-8)) !important;
  font-weight: normal !important;
}

:deep(.mx-datepicker-header) {
  color: rgb(var(--slate-12)) !important;
  border-bottom: 1px solid rgb(var(--slate-5)) !important;
}

:deep(.mx-btn) {
  color: rgb(var(--slate-12)) !important;
}

:deep(.mx-calendar-header-label) {
  color: rgb(var(--slate-12)) !important;
  font-weight: 600 !important;
}

.exc-cat-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.exc-select-wrap {
  display: flex;
  align-items: center;
  gap: 6px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  padding: 0 8px;
  height: 32px;
  transition: border-color 0.15s;
  position: relative;
}
.exc-select-wrap.focused {
  border-color: rgb(var(--blue-9));
  background: rgb(var(--slate-2));
}
.exc-select-ico {
  width: 12px;
  height: 12px;
  color: rgb(var(--slate-8));
  flex-shrink: 0;
}
.exc-select-value {
  flex: 1;
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  user-select: none;
  padding-top: 1px;
}
.exc-chevron {
  width: 12px;
  height: 12px;
  color: rgb(var(--slate-8));
  flex-shrink: 0;
}

.exc-select-wrap:hover {
  background: rgb(var(--slate-4));
  border-color: rgb(var(--slate-6));
}

/* Dropdown flutuante (teleport para body) */
.exc-select-trigger {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  @apply text-sm;
  color: rgb(var(--slate-12));
  cursor: pointer;
  transition: all 0.15s ease;
  min-height: 38px;
}
.exc-select-trigger:hover {
  background: rgb(var(--slate-4));
  border-color: rgb(var(--slate-6));
}
.exc-select-trigger.active {
  background: rgb(var(--slate-2));
  border-color: rgb(var(--blue-9));
  box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.1);
}

.exc-dropdown-floating {
  position: fixed;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  padding: 6px;
  box-shadow:
    0 8px 24px rgba(0, 0, 0, 0.12),
    0 2px 8px rgba(0, 0, 0, 0.08);
  display: flex;
  flex-direction: column;
  gap: 2px;
  z-index: 99999;
}
.exc-dropdown-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 7px 8px;
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-11));
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.1s;
  user-select: none;
}
.exc-dropdown-item:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}
.exc-dropdown-item.active {
  color: rgb(var(--blue-9));
}

/* Legado - mantém estrutura do wrapper */
.exc-cat-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

/* ───────── HOLIDAYS ───────── */
.holidays-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.holiday-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 9px 12px;
  gap: 10px;
  transition: border-color 0.15s;
}
.holiday-row:hover {
  border-color: rgb(var(--slate-7));
}
.hol-info {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}
.hol-name {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.hol-date {
  @apply text-sm;
  color: rgb(var(--slate-9));
  font-weight: 500;
}

.hol-toggle {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 10px;
  border-radius: 6px;
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  white-space: nowrap;
  flex-shrink: 0;
  user-select: none;
  border: 1px solid transparent;
  transition:
    all 0.15s,
    transform 0.1s;
}
.hol-toggle:hover {
  transform: scale(1.03);
}
.hol-toggle:active {
  transform: scale(0.97);
}
.hol-closed {
  background: rgba(239, 68, 68, 0.1);
  color: #ef4444;
  border-color: rgba(239, 68, 68, 0.3);
}
.hol-open {
  background: rgba(59, 130, 246, 0.1);
  color: rgb(var(--blue-9));
  border-color: rgba(59, 130, 246, 0.3);
}



/* ───────── EMPTY TAB ───────── */
.empty-tab {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  flex: 1;
  text-align: center;
  opacity: 0.6;
}
.empty-icon {
  width: 32px;
  height: 32px;
  color: rgb(var(--slate-8));
  margin-bottom: 14px;
}
.empty-title {
  font-size: 16px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  margin: 0 0 6px;
}
.empty-sub {
  @apply text-sm;
  color: rgb(var(--slate-10));
  margin: 0;
}



/* ─── AGENDAMENTO ONLINE ─────────────────────────────────────────── */
.online-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
  padding: 0 0 40px;
}
.online-col {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.online-card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 20px;
}
.online-card-title {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0 0 6px;
}
.online-card-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0 0 16px;
  line-height: 1.5;
}
/* Link público */
.link-input-group {
  display: flex;
  gap: 8px;
  align-items: center;
}
.link-readonly {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 8px 12px;
  overflow: hidden;
}
.link-ico {
  width: 14px;
  height: 14px;
  opacity: 0.5;
  flex-shrink: 0;
}
.link-text {
  @apply text-sm;
  color: rgb(var(--slate-11));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.copy-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  background: rgb(var(--brand-8));
  color: #fff;
  border: none;
  border-radius: 8px;
  @apply text-sm;
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  transition: background 0.15s;
}
.copy-btn:hover {
  background: rgb(var(--brand-9));
}
.link-hint {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 8px 0 0;
}
/* Regras */
.rules-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.rule-toggle-item,
.rule-row-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.rule-toggle-item:last-child,
.rule-row-item:last-child {
  border-bottom: none;
  padding-bottom: 0;
}
.rule-info {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.rule-label {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}
.rule-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  line-height: 1.4;
}
.rule-input-wrap {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}
.rule-num-input {
  width: 70px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  padding: 6px 8px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  text-align: center;
}
.rule-num-input:focus {
  outline: none;
  border-color: rgb(var(--blue-8));
}
.rule-unit {
  @apply text-sm;
  color: rgb(var(--slate-9));
}
/* Info note box - light theme friendly */
.info-note-box {
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-4));
}

/* Campos do formulário */
.fields-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.field-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  background: rgb(var(--slate-2));
  border-radius: 8px;
  border: 1px solid rgb(var(--slate-4));
}
.field-drag {
  color: rgb(var(--slate-9));
  cursor: grab;
}
.field-main {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
}
.field-label-text {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}
.field-type-tag {
  @apply text-sm;
  padding: 2px 6px;
  border-radius: 4px;
  background: rgb(var(--slate-5));
  color: rgb(var(--slate-10));
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.field-actions {
  display: flex;
  align-items: center;
  gap: 6px;
}
.field-req-badge {
  @apply text-sm;
  padding: 2px 6px;
  border-radius: 4px;
  background: rgb(var(--ruby-3));
  color: rgb(var(--ruby-11));
}
/* Seletor de agente (admin) */
.agent-selector-wrap {
  margin-bottom: 14px;
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.agent-selector-label {
  display: flex;
  align-items: center;
  gap: 5px;
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.agent-selector-select {
  width: 100%;
  background: rgb(var(--slate-2));
  border: 1.5px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 8px 10px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-family: inherit;
  cursor: pointer;
  transition: border-color 0.15s;
  outline: none;
}
.agent-selector-select:focus {
  border-color: rgb(var(--blue-8));
}

.rules-group-label {
  @apply text-sm;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: rgb(var(--slate-8));
  display: block;
}

.rule-row-modern {
  display: flex;
  align-items: center;
  gap: 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  padding: 10px 14px;
  transition: all 0.2s ease;
}
.rule-row-modern:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-3));
}

.rule-icon-sq {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.rule-info-main {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-width: 0;
}

.rule-label-main {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.rule-sub-main {
  @apply text-sm;
  color: rgb(var(--slate-8));
  line-height: 1.2;
}

.buffer-stepper {
  display: inline-flex;
  align-items: center;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  height: 32px;
  flex-shrink: 0;
  overflow: hidden;
}
.buffer-stepper-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 100%;
  padding: 0;
  background: transparent;
  border: none;
  color: rgb(var(--slate-11));
  cursor: pointer;
  transition: background 0.15s, color 0.15s;
}
.buffer-stepper-btn:hover:not(:disabled) {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}
.buffer-stepper-btn:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}
.buffer-stepper-value {
  min-width: 32px;
  padding: 0 4px;
  text-align: center;
  color: rgb(var(--slate-12));
  font-size: 13px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  border-left: 1px solid rgb(var(--slate-5));
  border-right: 1px solid rgb(var(--slate-5));
  line-height: 30px;
}

/* ───────── SAVING BUTTON (PREMIUM) ───────── */
.save-btn-premium {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: rgb(var(--blue-9));
  color: #fff;
  border: none;
  border-radius: 5px;
  padding: 6px 14px;
  @apply text-sm;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
}
.save-btn-premium:hover {
  background: rgb(var(--blue-10));
}
.save-btn-premium:active {
  transform: translateY(0);
}
.save-btn-premium.saving {
  opacity: 0.7;
  cursor: wait;
}

/* ───────── HOLIDAYS (CLEAN LIST) ───────── */
.holidays-section-modern {
  display: flex;
  flex-direction: column;
}

.holidays-list-clean {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.holiday-item-clean {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 14px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  cursor: pointer;
  transition: all 0.15s ease;
}

.holiday-item-clean:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-3));
}

.hol-indicator {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
}
.hol-indicator.closed {
  background: #ef4444;
  box-shadow: 0 0 8px rgba(239, 68, 68, 0.4);
}
.hol-indicator.open {
  background: #10b981;
  box-shadow: 0 0 8px rgba(16, 185, 129, 0.4);
}

.hol-content-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.hol-name-text {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.hol-date-text {
  @apply text-sm;
  color: rgb(var(--slate-8));
}

.hol-status-tag {
  @apply text-sm;
  font-weight: 700;
  text-transform: uppercase;
  padding: 2px 8px;
  border-radius: 6px;
}
.hol-status-tag.closed {
  background: rgba(239, 68, 68, 0.1);
  color: #dc2626;
}
.hol-status-tag.open {
  background: rgba(16, 185, 129, 0.1);
  color: #059669;
}

/* ─── Toggle Switch ─── */
.toggle-switch {
  position: relative;
  width: 44px;
  height: 24px;
  border-radius: 999px;
  border: none;
  background: rgb(var(--slate-6));
  cursor: pointer;
  transition: background 0.25s;
  flex-shrink: 0;
  padding: 0 !important;
  box-sizing: border-box !important;
}
.toggle-switch.toggle-on {
  background: rgb(var(--blue-9));
}
.toggle-switch.toggle-on.toggle-orange {
  background: #f97316;
}
.toggle-switch.toggle-on.toggle-rose {
  background: #f43f5e;
}
.toggle-thumb {
  position: absolute;
  top: 3px;
  left: 3px;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: #fff;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.35);
  transition: left 0.22s cubic-bezier(0.34, 1.56, 0.64, 1), transform 0.22s;
  padding: 0 !important;
  margin: 0 !important;
  box-sizing: border-box !important;
}
.toggle-switch.toggle-on .toggle-thumb {
  left: calc(100% - 21px);
  transform: none !important;
}
.toggle-switch:hover .toggle-thumb {
  box-shadow: 0 1px 6px rgba(0, 0, 0, 0.45);
}
.toggle-switch:focus-visible {
  outline: 2px solid rgb(var(--blue-9));
  outline-offset: 2px;
}

</style>
