<script>
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import ContactAPI from 'dashboard/api/contacts';
import DatePicker from 'vue-datepicker-next';
import 'vue-datepicker-next/index.css';
import { PRIORITIES, TREATMENTS, CUSTOM_ATTR_ICONS } from '../utils/agenda-constants.js';
import { padZ } from '../utils/agenda-date.js';
import { getPriorityColor } from '../utils/agenda-colors.js';

const PT_BR_LANG = {
  formatLocale: {
    months: ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'],
    monthsShort: ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'],
    weekdays: ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado'],
    weekdaysShort: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'],
    weekdaysMin: ['Do', 'Se', 'Te', 'Qu', 'Qu', 'Se', 'Sá'],
    firstDayOfWeek: 0,
    firstWeekContainsDate: 1,
  },
  monthBeforeYear: false,
};

const TAB_DEFS = [
  { value: 'consultation', label: 'Consulta', confirmKey: 'consulta', titleKey: 'Nova consulta' },
  { value: 'appointment', label: 'Compromisso', confirmKey: 'compromisso', titleKey: 'Novo compromisso' },
  { value: 'agenda_block', label: 'Bloqueio', confirmKey: 'bloqueio', titleKey: 'Novo bloqueio' },
];

export default {
  name: 'AgendaEventModal',
  components: { DatePicker },
  props: {
    show: { type: Boolean, default: false },
    isEditing: { type: Boolean, default: false },
    editingEventId: { type: [Number, String], default: null },
    newEvent: { type: Object, required: true },
    customAttributesConfig: { type: Array, default: () => [] },
    agents: { type: Array, default: () => [] },
    treatmentOptions: { type: Array, default: () => TREATMENTS },
    categoryOptions: { type: Array, default: () => [] },
    agendaSettings: { type: Object, default: () => null },
    isSlotBlocked: { type: Function, default: null },
    isSaving: { type: Boolean, default: false },
    isDeleting: { type: Boolean, default: false },
  },
  emits: ['close', 'save', 'delete', 'update:newEvent'],
  data() {
    return {
      // Active tab
      activeTab: 'consultation',

      // Dropdown states
      priorityOpen: false,
      prioritySearch: '',
      treatmentOpen: false,
      treatmentSearch: '',
      categoryOpen: false,
      categorySearch: '',
      agentOpen: false,
      agentSearch: '',
      patientOpen: false,
      patientSearch: '',

      // Patient lists
      patientList: [],

      // Quick Patient Modal
      showQuickPatientModal: false,
      quickPatient: { name: '', last_name: '', phone: '' },
      isSubmittingPatient: false,
      quickPatientPhoneOpen: false,
      quickPatientPhoneSuggestions: [],

      // Debounce timers
      _patientDebounce: null,
      _phoneDebounce: null,
    };
  },
  computed: {
    ptBrLang() {
      return PT_BR_LANG;
    },
    tabs() {
      return TAB_DEFS;
    },
    activeTabDef() {
      return TAB_DEFS.find(t => t.value === this.activeTab) || TAB_DEFS[0];
    },
    headerTitle() {
      if (this.isEditing) {
        return `Editar ${this.activeTabDef.confirmKey}`;
      }
      return this.activeTabDef.titleKey;
    },
    confirmButtonLabel() {
      if (this.isSaving) return this.$t('AGENDA.MODAL.BTN_SAVING');
      if (this.activeTab === 'agenda_block') return 'Bloquear agenda';
      return `Confirmar ${this.activeTabDef.confirmKey}`;
    },
    selectedPriorityLabel() {
      const found = PRIORITIES.find(p => p.value === this.newEvent.priority);
      return found ? found.label : 'Selecione';
    },
    filteredPriorities() {
      const q = this.prioritySearch.toLowerCase();
      return PRIORITIES.filter(p => p.label.toLowerCase().includes(q));
    },
    filteredTreatments() {
      const q = this.treatmentSearch.toLowerCase();
      return this.treatmentOptions.filter(tr => {
        const name = typeof tr === 'string' ? tr : tr.name || '';
        return name.toLowerCase().includes(q);
      });
    },
    filteredCategories() {
      const q = this.categorySearch.toLowerCase();
      return (this.categoryOptions || []).filter(c =>
        (c.name || '').toLowerCase().includes(q)
      );
    },
    selectedCategory() {
      const id = this.newEvent.category_id;
      if (!id) return null;
      return (this.categoryOptions || []).find(c => c.id === id) || null;
    },
    filteredAgents() {
      const q = this.agentSearch.toLowerCase();
      return this.agents.filter(a => (a.name || '').toLowerCase().includes(q));
    },
    selectedAgentLabel() {
      const a = this.agents.find(x => x.id === this.newEvent.user_id);
      return a?.name || '';
    },
    selectedTreatmentColor() {
      const name = this.newEvent.treatment;
      if (!name) return null;
      const found = this.treatmentOptions.find(
        t => (typeof t === 'string' ? t : t.name) === name
      );
      return found && typeof found === 'object' ? found.color : null;
    },
    hasPatientSelected() {
      return Boolean(this.newEvent.patient_id || this.newEvent.selectedPatientName);
    },
    canConfirm() {
      if (this.isSaving) return false;
      if (!this.newEvent.time_start || !this.newEvent.time_end) return false;
      if (this.activeTab === 'consultation') {
        return Boolean(this.newEvent.selectedPatientName) && Boolean(this.newEvent.user_id);
      }
      return Boolean(this.newEvent.title) && Boolean(this.newEvent.user_id);
    },
    slotInterval() {
      return this.agendaSettings?.slot_interval_minutes || 60;
    },
    slotRange() {
      const settings = this.agendaSettings;
      // When the clinic enforces working hours, mirror the same range. Otherwise
      // expose the full day so users can still create events off-hours.
      if (
        settings?.block_outside_working_hours &&
        Array.isArray(settings.week_days)
      ) {
        const enabled = settings.week_days.filter(d => d.enabled && d.start && d.end);
        if (enabled.length) {
          const startH = Math.min(
            ...enabled.map(d => parseInt(d.start.split(':')[0], 10))
          );
          const endH = Math.max(
            ...enabled.map(d => {
              const [h, m] = d.end.split(':').map(Number);
              return m > 0 ? h + 1 : h;
            })
          );
          return { startH, endH };
        }
      }
      return { startH: 0, endH: 24 };
    },
    selectedDayObj() {
      if (!this.newEvent.date) return null;
      const [y, mo, d] = this.newEvent.date.split('-').map(Number);
      return { year: y, month: mo - 1, day: d };
    },
    timeSlots() {
      const slots = [];
      const { startH, endH } = this.slotRange;
      const interval = this.slotInterval;
      for (let h = startH; h < endH; h += 1) {
        for (let m = 0; m < 60; m += interval) {
          slots.push(`${padZ(h)}:${padZ(m)}`);
        }
      }
      return slots;
    },
    rangeLabel() {
      if (!this.newEvent.time_start || !this.newEvent.time_end) {
        return 'Selecione um horário';
      }
      return `${this.newEvent.time_start} - ${this.newEvent.time_end}`;
    },
    todayDateStr() {
      const d = new Date();
      return `${d.getFullYear()}-${padZ(d.getMonth() + 1)}-${padZ(d.getDate())}`;
    },
    isDateToday() {
      return this.newEvent.date === this.todayDateStr;
    },
    customAttributesGridClass() {
      // 1 campo → ocupa 100% (uma coluna). 2+ campos → grid 2 colunas em
      // desktop, 1 coluna em mobile. Atributos do tipo `textarea` quebram
      // para a linha inteira via `sm:col-span-2` no item.
      const count = this.customAttributesConfig?.length || 0;
      return count <= 1 ? 'grid-cols-1' : 'grid-cols-1 sm:grid-cols-2';
    },
  },
  watch: {
    show(val) {
      if (val) {
        this.activeTab = this.newEvent.event_type || 'consultation';
        this.fetchPatients('');
      } else {
        this.priorityOpen = false;
        this.treatmentOpen = false;
        this.categoryOpen = false;
        this.agentOpen = false;
        this.patientOpen = false;
        this.quickPatientPhoneOpen = false;
        this.prioritySearch = '';
        this.treatmentSearch = '';
        this.categorySearch = '';
        this.agentSearch = '';
        this.patientSearch = '';
      }
    },
    activeTab(newVal, oldVal) {
      if (!this.show || this.newEvent.event_type === newVal) return;
      const update = { event_type: newVal };
      // Clear patient-bound data when leaving Consulta — appointment/block don't use a patient.
      if (oldVal === 'consultation' && newVal !== 'consultation') {
        update.title = '';
        update.contact_id = null;
        update.patient_id = null;
        update.selectedPatientName = '';
        update.selectedPatientPhone = '';
        update.selectedPatientAvatarUrl = null;
      }
      // Clear free-form title when entering Consulta — title will be set from the chosen patient.
      if (newVal === 'consultation' && oldVal !== 'consultation') {
        if (!this.newEvent.selectedPatientName) update.title = '';
      }
      this.emitUpdate(update);
    },
  },
  mounted() {
    // Capture phase: the modal's outer wrapper has @click.stop, which would
    // otherwise prevent this listener from ever firing for clicks inside the
    // modal but outside the dropdowns. Capture runs before stopPropagation.
    document.addEventListener('click', this.handleClickOutside, true);
  },
  unmounted() {
    document.removeEventListener('click', this.handleClickOutside, true);
  },
  methods: {
    getPriorityColor,
    padZ,
    toMinutes(t) {
      if (!t) return 0;
      const [h, m] = t.split(':').map(Number);
      return h * 60 + (m || 0);
    },
    fromMinutes(min) {
      const h = Math.floor(min / 60) % 24;
      const m = min % 60;
      return `${padZ(h)}:${padZ(m)}`;
    },
    isSlotInRange(slot) {
      if (!this.newEvent.time_start || !this.newEvent.time_end) return false;
      const v = this.toMinutes(slot);
      const s = this.toMinutes(this.newEvent.time_start);
      const e = this.toMinutes(this.newEvent.time_end);
      return v >= s && v < e;
    },
    slotBlockedReason(slot) {
      if (typeof this.isSlotBlocked !== 'function') return null;
      if (!this.selectedDayObj) return null;
      const reason = this.isSlotBlocked(this.selectedDayObj, slot);
      if (!reason) return null;
      return reason === true ? 'Indisponível' : reason;
    },
    selectSlot(slot) {
      if (this.slotBlockedReason(slot)) return;
      const slotMin = this.toMinutes(slot);
      // No selection yet → this click defines the start; reserve a single slot.
      if (!this.newEvent.time_start || !this.newEvent.time_end) {
        this.emitUpdate({
          time_start: slot,
          time_end: this.fromMinutes(slotMin + this.slotInterval),
        });
        return;
      }
      const startMin = this.toMinutes(this.newEvent.time_start);
      const endMin = this.toMinutes(this.newEvent.time_end);

      if (slotMin >= endMin) {
        this.emitUpdate({ time_end: this.fromMinutes(slotMin + this.slotInterval) });
      } else if (slotMin < startMin || (slotMin >= startMin && slotMin < endMin)) {
        this.emitUpdate({
          time_start: slot,
          time_end: this.fromMinutes(slotMin + this.slotInterval),
        });
      }
    },
    getAgentColorById(id) {
      const a = this.agents.find(x => x.id === id);
      return a?.color || '#3b82f6';
    },
    handleClickOutside(e) {
      if (!this.show) return;
      if (!e.target.closest('.custom-select') && !e.target.closest('.cs-dropdown') && !e.target.closest('[data-patient-picker]')) {
        this.priorityOpen = false;
        this.treatmentOpen = false;
        this.categoryOpen = false;
        this.agentOpen = false;
        this.patientOpen = false;
        this.quickPatientPhoneOpen = false;
      }
    },
    toggleDropdown(name) {
      const keys = ['priority', 'treatment', 'category', 'agent'];
      keys.forEach(k => {
        if (k !== name) this[`${k}Open`] = false;
      });
      this[`${name}Open`] = !this[`${name}Open`];
    },
    selectCategory(c) {
      this.emitUpdate({ category_id: c.id });
      this.categoryOpen = false;
      this.categorySearch = '';
    },
    clearCategory() {
      this.emitUpdate({ category_id: null });
      this.categoryOpen = false;
      this.categorySearch = '';
    },
    selectPriority(p) {
      this.emitUpdate({ priority: p.value });
      this.priorityOpen = false;
      this.prioritySearch = '';
    },
    selectAgent(a) {
      this.emitUpdate({ user_id: a.id });
      this.agentOpen = false;
      this.agentSearch = '';
    },
    selectTreatment(tr) {
      const name = typeof tr === 'string' ? tr : tr.name;
      const update = { treatment: name };
      if (tr && tr.duration_minutes) {
        const interval = this.slotInterval;
        // Round duration UP to the nearest whole slot so the auto-selected
        // range always lands exactly on grid boundaries (e.g. 45-min service
        // with 30-min slots → 60 min = 2 slots; never 1.5). Spec: NEVER use
        // Math.floor — selections must cover the FULL service duration.
        const slotsNeeded = Math.max(1, Math.ceil(tr.duration_minutes / interval));
        const alignedDuration = slotsNeeded * interval;

        // If the user has not picked a start yet, anchor at the first
        // non-blocked slot of the day so the service auto-selection still
        // produces a valid range.
        let startMin = null;
        if (this.newEvent.time_start) {
          startMin = this.toMinutes(this.newEvent.time_start);
        } else {
          const firstFree = this.timeSlots.find(s => !this.slotBlockedReason(s));
          if (firstFree) {
            update.time_start = firstFree;
            startMin = this.toMinutes(firstFree);
          }
        }
        if (startMin != null) {
          update.time_end = this.fromMinutes(startMin + alignedDuration);
        }
      }
      this.emitUpdate(update);
      this.treatmentOpen = false;
      this.treatmentSearch = '';
    },
    clearTreatment() {
      this.emitUpdate({ treatment: '' });
      this.treatmentOpen = false;
      this.treatmentSearch = '';
    },

    // Patient picker
    onPatientSearchInput() {
      clearTimeout(this._patientDebounce);
      this._patientDebounce = setTimeout(() => {
        this.fetchPatients(this.patientSearch);
      }, 250);
    },
    onPatientFocus() {
      this.patientOpen = true;
      if (!this.patientList.length) {
        this.fetchPatients(this.patientSearch);
      }
    },
    selectContact(patient) {
      this.emitUpdate({
        contact_id: patient.contact_id || null,
        patient_id: patient.id,
        selectedPatientName: patient.name,
        selectedPatientPhone: patient.phone || '',
        selectedPatientAvatarUrl: patient.avatar_url || null,
        title: patient.name,
      });
      this.patientOpen = false;
      this.patientSearch = '';
    },
    clearPatient() {
      this.emitUpdate({
        contact_id: null,
        patient_id: null,
        selectedPatientName: '',
        selectedPatientPhone: '',
        selectedPatientAvatarUrl: null,
        title: '',
      });
      this.patientSearch = '';
      this.fetchPatients('');
      this.patientOpen = true;
      this.$nextTick(() => {
        const el = this.$refs.patientInput;
        if (el && el.focus) el.focus();
      });
    },

    async fetchPatients(query = '') {
      try {
        const response = await PatientsAPI.get({ page: 1, perPage: 25, search: query });
        if (response.data && response.data.payload) {
          this.patientList = response.data.payload;
        }
      } catch {
        // ignore
      }
    },

    // Quick Patient
    openNewPatientModal() {
      this.showQuickPatientModal = true;
      this.quickPatient = { name: this.patientSearch || '', last_name: '', phone: '' };
    },
    closeQuickPatientModal() {
      this.showQuickPatientModal = false;
    },
    formatQuickPatientPhone() {
      let phone = this.quickPatient.phone.replace(/\D/g, '');
      if (phone.length > 11) phone = phone.slice(0, 11);
      if (phone.length > 6) {
        phone = `(${phone.slice(0, 2)}) ${phone.slice(2, 7)}-${phone.slice(7)}`;
      } else if (phone.length > 2) {
        phone = `(${phone.slice(0, 2)}) ${phone.slice(2)}`;
      }
      this.quickPatient.phone = phone;

      clearTimeout(this._phoneDebounce);
      this._phoneDebounce = setTimeout(() => {
        this.fetchPhoneSuggestions();
      }, 300);
    },
    async fetchPhoneSuggestions() {
      const digits = this.quickPatient.phone.replace(/\D/g, '');
      if (digits.length < 4) {
        this.quickPatientPhoneSuggestions = [];
        this.quickPatientPhoneOpen = false;
        return;
      }
      try {
        const resp = await ContactAPI.search(digits);
        const contacts = resp.data?.payload || [];
        this.quickPatientPhoneSuggestions = contacts.slice(0, 5);
        this.quickPatientPhoneOpen = this.quickPatientPhoneSuggestions.length > 0;
      } catch {
        // ignore
      }
    },
    selectPhoneSuggestion(sug) {
      this.selectContact({
        id: sug.patient_id || sug.id,
        contact_id: sug.id,
        name: sug.name,
        phone: sug.phone_number || sug.phone || '',
        avatar_url: sug.thumbnail || null,
      });
      this.closeQuickPatientModal();
    },
    async submitQuickPatient() {
      if (!this.quickPatient.name) return;
      this.isSubmittingPatient = true;
      try {
        const payload = {
          name: this.quickPatient.name,
          last_name: this.quickPatient.last_name,
          phone: this.quickPatient.phone.replace(/\D/g, ''),
        };
        const res = await PatientsAPI.create(payload);
        const patient = res.data;
        this.selectContact({
          id: patient.id,
          contact_id: patient.contact_id || null,
          name: patient.name,
          phone: patient.phone || '',
          avatar_url: patient.avatar_url || null,
        });
        this.closeQuickPatientModal();
      } catch {
        // ignore
      } finally {
        this.isSubmittingPatient = false;
      }
    },

    // Custom attributes helpers
    getTypeIcon(type) {
      return CUSTOM_ATTR_ICONS[type] || 'i-lucide-file-text';
    },
    getOptions(options) {
      if (typeof options === 'string') {
        try {
          return JSON.parse(options);
        } catch {
          return options.split(',').map(s => s.trim());
        }
      }
      return options || [];
    },
    isDynamicCpfValid(attr) {
      const val = this.newEvent.custom_values[`attr_${attr.id}`];
      if (!val || val.length < 4) return true;
      const digits = String(val).replace(/\D/g, '');
      return digits.length === 11;
    },
    formatDynamicCpfInput(e, key) {
      let val = e.target.value.replace(/\D/g, '');
      if (val.length > 11) val = val.slice(0, 11);
      if (val.length > 9) {
        val = `${val.slice(0, 3)}.${val.slice(3, 6)}.${val.slice(6, 9)}-${val.slice(9)}`;
      } else if (val.length > 6) {
        val = `${val.slice(0, 3)}.${val.slice(3, 6)}.${val.slice(6)}`;
      } else if (val.length > 3) {
        val = `${val.slice(0, 3)}.${val.slice(3)}`;
      }
      this.emitUpdate({ custom_values: { ...this.newEvent.custom_values, [key]: val } });
    },
    formatDynamicPhoneInput(e, key) {
      let val = e.target.value.replace(/\D/g, '');
      if (val.length > 11) val = val.slice(0, 11);
      if (val.length > 6) {
        val = `(${val.slice(0, 2)}) ${val.slice(2, 7)}-${val.slice(7)}`;
      } else if (val.length > 2) {
        val = `(${val.slice(0, 2)}) ${val.slice(2)}`;
      }
      this.emitUpdate({ custom_values: { ...this.newEvent.custom_values, [key]: val } });
    },
    updateCustomValue(key, value) {
      this.emitUpdate({
        custom_values: { ...this.newEvent.custom_values, [key]: value },
      });
    },

    onTitleInput(value) {
      const update = { title: value };
      if (this.activeTab !== 'consultation') {
        update.selectedPatientName = '';
      }
      this.emitUpdate(update);
    },

    // Emit helper
    emitUpdate(partial) {
      this.$emit('update:newEvent', { ...this.newEvent, ...partial });
    },

    getInitials(name) {
      if (!name) return '';
      const parts = name.trim().split(/\s+/);
      if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
      return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    },
  },
};
</script>

<template>
  <Teleport to="body">
    <transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition duration-150 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        class="fixed inset-0 z-[1000] flex items-center justify-center bg-black/75 backdrop-blur-md sm:p-4 modal-overlay-responsive"
        @click.self="$emit('close')"
      >
        <div class="flex items-stretch w-full h-full sm:w-auto sm:h-auto sm:max-h-[calc(100vh-2rem)]" @click.stop>
          <!-- ── MAIN MODAL ── -->
          <div
            class="agenda-new-event-modal w-full h-full sm:w-[640px] sm:h-auto bg-n-solid-1 sm:shadow-2xl border-0 sm:border border-n-weak flex flex-col z-20 transition-all duration-300"
            :class="
              showQuickPatientModal
                ? 'rounded-none sm:rounded-l-2xl sm:border-r-0'
                : 'rounded-none sm:rounded-2xl'
            "
          >
            <!-- Header -->
            <div class="flex items-center justify-between px-4 sm:px-6 border-b border-n-weak shrink-0 min-h-[60px] sm:min-h-[68px]">
              <div class="flex items-center gap-3 min-w-0">
                <div class="flex items-center justify-center w-9 h-9 rounded-xl bg-n-blue-2 text-n-blue-11 text-base shrink-0">
                  <i :class="activeTab === 'agenda_block' ? 'i-lucide-calendar-x' : activeTab === 'appointment' ? 'i-lucide-calendar-clock' : 'i-lucide-calendar-plus'" />
                </div>
                <div class="min-w-0">
                  <h3 class="text-base font-semibold text-n-slate-12 leading-tight truncate">
                    {{ headerTitle }}
                  </h3>
                  <span v-if="isEditing" class="text-xs text-n-slate-10 mt-0.5 block">
                    #{{ editingEventId }}
                  </span>
                </div>
              </div>
              <button
                class="flex items-center justify-center w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors shrink-0 p-0"
                @click="$emit('close')"
              >
                <i class="i-lucide-x w-4 h-4" />
              </button>
            </div>

            <!-- Tabs (Segmented Control) -->
            <div class="px-4 sm:px-6 pt-4 sm:pt-5 shrink-0">
              <div class="inline-flex p-1 bg-n-alpha-1 rounded-xl gap-1 w-full sm:w-auto">
                <button
                  v-for="tab in tabs"
                  :key="tab.value"
                  type="button"
                  class="flex-1 sm:flex-none px-4 py-1.5 text-sm font-medium rounded-lg transition-all duration-150"
                  :class="
                    activeTab === tab.value
                      ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                      : 'text-n-slate-10 hover:text-n-slate-12'
                  "
                  @click="activeTab = tab.value"
                >
                  {{ tab.label }}
                </button>
              </div>
            </div>

            <!-- Body -->
            <div class="px-4 sm:px-6 py-5 flex-1 overflow-y-auto flex flex-col gap-5 modal-scroll">
              <!-- ── CONSULTA TAB ── -->
              <template v-if="activeTab === 'consultation'">
                <!-- Patient Picker (focal) -->
                <div data-patient-picker>
                  <div v-if="!hasPatientSelected" class="relative">
                    <div class="relative">
                      <input
                        ref="patientInput"
                        v-model="patientSearch"
                        type="text"
                        class="w-full px-3 py-3 text-base bg-n-solid-1 border border-n-weak rounded-xl text-n-slate-12 placeholder:text-n-slate-9 outline-none transition-all focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-9/20"
                        placeholder="Nome do paciente"
                        @focus="onPatientFocus"
                        @input="onPatientSearchInput"
                      />
                    </div>
                    <div
                      v-if="patientOpen"
                      class="absolute z-50 w-full mt-1 bg-n-solid-1 border border-n-weak rounded-xl shadow-xl overflow-hidden max-h-72 overflow-y-auto"
                    >
                      <button
                        type="button"
                        class="w-full flex items-center gap-2 px-3 py-2.5 text-sm text-n-blue-11 hover:bg-n-alpha-2 transition-colors text-left font-medium"
                        @mousedown.prevent="openNewPatientModal"
                      >
                        <i class="i-lucide-user-plus w-4 h-4" />
                        <template v-if="patientSearch">
                          Cadastrar novo paciente: <span class="font-semibold">{{ patientSearch }}</span>
                        </template>
                        <template v-else>
                          Cadastrar novo paciente
                        </template>
                      </button>
                      <div v-if="patientList.length" class="border-t border-n-weak">
                        <div class="px-3 pt-2 pb-1 text-xs font-semibold text-n-slate-10 uppercase tracking-wider">
                          Pacientes
                        </div>
                        <button
                          v-for="patient in patientList"
                          :key="patient.id"
                          type="button"
                          class="w-full flex items-center gap-2.5 px-3 py-2 hover:bg-n-alpha-2 transition-colors text-left"
                          @mousedown.prevent="selectContact(patient)"
                        >
                          <span class="flex items-center justify-center w-7 h-7 rounded-full bg-n-blue-2 text-n-blue-11 text-xs font-semibold shrink-0">
                            {{ getInitials(patient.name) }}
                          </span>
                          <span class="text-sm text-n-slate-12 truncate">{{ patient.name }}</span>
                          <span v-if="patient.phone" class="text-xs text-n-slate-10 ml-auto">{{ patient.phone }}</span>
                        </button>
                      </div>
                      <div v-else-if="patientSearch" class="px-3 py-3 text-sm text-n-slate-10 italic text-center border-t border-n-weak">
                        Nenhum paciente encontrado
                      </div>
                    </div>
                  </div>
                  <!-- Selected patient summary card -->
                  <div v-else class="border border-n-weak rounded-xl bg-n-alpha-1 px-4 py-3 flex items-center gap-3">
                    <span class="flex items-center justify-center w-10 h-10 rounded-full bg-n-blue-2 text-n-blue-11 text-sm font-semibold shrink-0">
                      {{ getInitials(newEvent.selectedPatientName) }}
                    </span>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-semibold text-n-slate-12 truncate">
                        {{ newEvent.selectedPatientName }}
                      </div>
                      <div class="text-xs text-n-slate-10 truncate">
                        Telefone: {{ newEvent.selectedPatientPhone || 'Não informado' }}
                      </div>
                    </div>
                    <button
                      type="button"
                      class="text-sm font-medium text-n-blue-11 hover:underline shrink-0"
                      @click="clearPatient"
                    >
                      Trocar
                    </button>
                  </div>
                </div>

                <!-- Observações -->
                <div class="form-group">
                  <label class="form-label">
                    <i class="i-lucide-file-text label-icon" />
                    Observações
                  </label>
                  <textarea
                    :value="newEvent.description"
                    class="form-input"
                    rows="2"
                    placeholder="Adicione notas, sintomas, instruções..."
                    @input="e => emitUpdate({ description: e.target.value })"
                  />
                </div>

                <!-- Serviço (campo `treatment` no schema mantido por compat) -->
                <div class="form-group">
                  <label class="form-label">
                    <i class="i-lucide-activity label-icon" />
                    Serviço
                  </label>
                  <div class="custom-select" :class="{ open: treatmentOpen }">
                    <button class="cs-trigger" type="button" @click="toggleDropdown('treatment')">
                      <span class="cs-trigger-content">
                        <span
                          v-if="selectedTreatmentColor"
                          class="cs-svc-dot"
                          :style="{ background: selectedTreatmentColor }"
                        />
                        {{ newEvent.treatment || 'Selecione um serviço' }}
                      </span>
                      <i class="i-lucide-chevron-down cs-arrow" />
                    </button>
                    <div v-if="treatmentOpen" class="cs-dropdown">
                      <input v-model="treatmentSearch" class="cs-search" placeholder="Buscar..." @click.stop />
                      <div
                        v-if="newEvent.treatment"
                        class="cs-option !text-n-slate-10 !flex items-center gap-2"
                        @click.stop="clearTreatment"
                      >
                        <i class="i-lucide-x w-3.5 h-3.5" />
                        Limpar seleção
                      </div>
                      <div
                        v-for="tr in filteredTreatments"
                        :key="typeof tr === 'string' ? tr : tr.id"
                        class="cs-option cs-option-service"
                        :class="{ selected: newEvent.treatment === (typeof tr === 'string' ? tr : tr.name) }"
                        @click="selectTreatment(tr)"
                      >
                        <span v-if="tr && tr.color" class="cs-svc-dot" :style="{ background: tr.color }" />
                        <span class="cs-svc-name">{{ typeof tr === 'string' ? tr : tr.name }}</span>
                        <span v-if="tr && tr.duration_minutes" class="cs-svc-dur">
                          {{ Math.floor(tr.duration_minutes / 60) > 0 ? Math.floor(tr.duration_minutes / 60) + 'h' : '' }}{{ tr.duration_minutes % 60 > 0 ? (tr.duration_minutes % 60) + 'min' : '' }}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Categoria -->
                <div v-if="categoryOptions && categoryOptions.length" class="form-group">
                  <label class="form-label">
                    <i class="i-lucide-tag label-icon" />
                    Categoria
                  </label>
                  <div class="custom-select" :class="{ open: categoryOpen }">
                    <button class="cs-trigger" type="button" @click="toggleDropdown('category')">
                      <span class="cs-trigger-content">
                        <span
                          v-if="selectedCategory"
                          class="cs-svc-dot"
                          :style="{ background: selectedCategory.color }"
                        />
                        {{ selectedCategory ? selectedCategory.name : 'Selecionar categoria' }}
                      </span>
                      <i class="i-lucide-chevron-down cs-arrow" />
                    </button>
                    <div v-if="categoryOpen" class="cs-dropdown">
                      <input v-model="categorySearch" class="cs-search" placeholder="Buscar..." @click.stop />
                      <div
                        v-if="newEvent.category_id"
                        class="cs-option !text-n-slate-10 !flex items-center gap-2"
                        @click.stop="clearCategory"
                      >
                        <i class="i-lucide-x w-3.5 h-3.5" />
                        Limpar seleção
                      </div>
                      <div
                        v-for="c in filteredCategories"
                        :key="c.id"
                        class="cs-option cs-option-service"
                        :class="{ selected: newEvent.category_id === c.id }"
                        @click="selectCategory(c)"
                      >
                        <span class="cs-svc-dot" :style="{ background: c.color }" />
                        <span class="cs-svc-name">{{ c.name }}</span>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Custom Attributes -->
                <div
                  v-if="customAttributesConfig && customAttributesConfig.length"
                  class="grid gap-4"
                  :class="customAttributesGridClass"
                >
                  <div
                    v-for="attr in customAttributesConfig"
                    :key="attr.id"
                    class="form-group"
                    :class="{ 'sm:col-span-2': attr.type === 'textarea' }"
                  >
                    <label class="form-label">
                      <i :class="getTypeIcon(attr.type)" class="label-icon" />
                      {{ attr.name }}
                      <span v-if="attr.required" class="text-red-400 ml-0.5">*</span>
                    </label>
                    <select
                      v-if="attr.type === 'select'"
                      :value="newEvent.custom_values[`attr_${attr.id}`]"
                      class="form-input form-select"
                      @change="e => updateCustomValue(`attr_${attr.id}`, e.target.value)"
                    >
                      <option value="" disabled>Selecione</option>
                      <option v-for="opt in getOptions(attr.options)" :key="opt" :value="opt">{{ opt }}</option>
                    </select>
                    <textarea
                      v-else-if="attr.type === 'textarea'"
                      :value="newEvent.custom_values[`attr_${attr.id}`]"
                      class="form-input"
                      rows="3"
                      @input="e => updateCustomValue(`attr_${attr.id}`, e.target.value)"
                    />
                    <input
                      v-else-if="attr.type === 'date'"
                      :value="newEvent.custom_values[`attr_${attr.id}`]"
                      type="date"
                      class="form-input"
                      @input="e => updateCustomValue(`attr_${attr.id}`, e.target.value)"
                    />
                    <input
                      v-else-if="attr.type === 'phone'"
                      :value="newEvent.custom_values[`attr_${attr.id}`]"
                      type="text"
                      class="form-input"
                      placeholder="(00) 00000-0000"
                      maxlength="15"
                      inputmode="tel"
                      @input="e => formatDynamicPhoneInput(e, `attr_${attr.id}`)"
                    />
                    <div v-else-if="attr.type === 'cpf'">
                      <input
                        :value="newEvent.custom_values[`attr_${attr.id}`]"
                        type="text"
                        class="form-input"
                        :class="{ 'error-input': !isDynamicCpfValid(attr) }"
                        placeholder="000.000.000-00"
                        maxlength="14"
                        inputmode="numeric"
                        @input="e => formatDynamicCpfInput(e, `attr_${attr.id}`)"
                      />
                      <span v-if="!isDynamicCpfValid(attr)" class="error-msg">CPF inválido</span>
                    </div>
                    <input
                      v-else
                      :value="newEvent.custom_values[`attr_${attr.id}`]"
                      type="text"
                      class="form-input"
                      @input="e => updateCustomValue(`attr_${attr.id}`, e.target.value)"
                    />
                  </div>
                </div>

                <!-- Configuração: Profissional + Prioridade -->
                <div class="border-t border-n-weak pt-5 grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div class="form-group">
                    <label class="form-label">
                      <i class="i-lucide-user label-icon" />
                      {{ $t('AGENDA.MODAL.FIELD_AGENT') }}
                    </label>
                    <div class="custom-select" :class="{ open: agentOpen }">
                      <button class="cs-trigger" type="button" @click="toggleDropdown('agent')">
                        <span class="cs-trigger-content">
                          <span
                            v-if="newEvent.user_id"
                            class="cs-svc-dot"
                            :style="{ background: getAgentColorById(newEvent.user_id) }"
                          />
                          {{ selectedAgentLabel || 'Selecione' }}
                        </span>
                        <i class="i-lucide-chevron-down cs-arrow" />
                      </button>
                      <div v-if="agentOpen" class="cs-dropdown">
                        <input v-model="agentSearch" class="cs-search" placeholder="Buscar..." @click.stop />
                        <div
                          v-for="a in filteredAgents"
                          :key="a.id"
                          class="cs-option cs-option-service"
                          :class="{ selected: newEvent.user_id === a.id }"
                          @click="selectAgent(a)"
                        >
                          <span class="cs-svc-dot" :style="{ background: a.color }" />
                          <span class="cs-svc-name">{{ a.name }}</span>
                        </div>
                      </div>
                    </div>
                  </div>
                  <div class="form-group">
                    <label class="form-label">
                      <i class="i-lucide-alert-circle label-icon" />
                      Prioridade
                    </label>
                    <div class="custom-select" :class="{ open: priorityOpen }">
                      <button class="cs-trigger" type="button" @click="toggleDropdown('priority')">
                        <span class="cs-trigger-content">
                          <span
                            class="cs-svc-dot"
                            :style="{ background: getPriorityColor(newEvent.priority) }"
                          />
                          {{ selectedPriorityLabel }}
                        </span>
                        <i class="i-lucide-chevron-down cs-arrow" />
                      </button>
                      <div v-if="priorityOpen" class="cs-dropdown">
                        <input v-model="prioritySearch" class="cs-search" placeholder="Buscar..." @click.stop />
                        <div
                          v-for="p in filteredPriorities"
                          :key="p.value"
                          class="cs-option cs-option-service"
                          :class="{ selected: newEvent.priority === p.value }"
                          @click="selectPriority(p)"
                        >
                          <span class="cs-svc-dot" :style="{ background: getPriorityColor(p.value) }" />
                          <span class="cs-svc-name">{{ p.label }}</span>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Data + Slot Grid -->
                <div class="border-t border-n-weak pt-5 flex flex-col gap-4">
                  <div class="form-group sm:max-w-xs">
                    <label class="form-label">
                      <i class="i-lucide-calendar label-icon" />
                      Data
                    </label>
                    <div class="flex items-center gap-2">
                      <DatePicker
                        :value="newEvent.date"
                        type="date"
                        value-type="YYYY-MM-DD"
                        format="DD/MM/YYYY"
                        :lang="ptBrLang"
                        :clearable="false"
                        :editable="false"
                        class="modal-datepicker flex-1"
                        append-to-body
                        @update:value="v => emitUpdate({ date: v })"
                      />
                      <button
                        type="button"
                        class="datepicker-today-btn"
                        :class="{ 'datepicker-today-btn--active': isDateToday }"
                        :disabled="isDateToday"
                        @click="emitUpdate({ date: todayDateStr })"
                      >
                        Hoje
                      </button>
                    </div>
                  </div>
                  <div>
                    <div class="flex items-baseline justify-between mb-2">
                      <label class="form-label !mb-0">
                        <i class="i-lucide-clock label-icon" />
                        Horário
                      </label>
                      <span class="text-sm font-semibold text-n-blue-11 tabular-nums">{{ rangeLabel }}</span>
                    </div>
                    <div class="grid grid-cols-[repeat(auto-fill,minmax(58px,1fr))] gap-1.5">
                      <button
                        v-for="slot in timeSlots"
                        :key="slot"
                        type="button"
                        class="slot-btn"
                        :class="{
                          'slot-btn--start': slot === newEvent.time_start && !slotBlockedReason(slot),
                          'slot-btn--in-range': isSlotInRange(slot) && slot !== newEvent.time_start && !slotBlockedReason(slot),
                          'slot-btn--blocked': !!slotBlockedReason(slot),
                        }"
                        :disabled="!!slotBlockedReason(slot)"
                        :title="slotBlockedReason(slot) || ''"
                        @click="selectSlot(slot)"
                      >
                        {{ slot }}
                      </button>
                    </div>
                  </div>
                </div>
              </template>

              <!-- ── COMPROMISSO / BLOQUEIO TAB ── -->
              <template v-else>
                <!-- Title -->
                <div class="form-group">
                  <input
                    :value="newEvent.title"
                    type="text"
                    class="w-full px-3 py-3 text-base bg-n-solid-1 border border-n-weak rounded-xl text-n-slate-12 placeholder:text-n-slate-9 outline-none transition-all focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-9/20"
                    :placeholder="activeTab === 'agenda_block' ? 'Motivo do bloqueio' : 'Nome do compromisso'"
                    @input="e => onTitleInput(e.target.value)"
                  />
                </div>

                <!-- Profissional -->
                <div class="form-group">
                  <label class="form-label">
                    <i class="i-lucide-user label-icon" />
                    {{ $t('AGENDA.MODAL.FIELD_AGENT') }}
                  </label>
                  <div class="custom-select" :class="{ open: agentOpen }">
                    <button class="cs-trigger" type="button" @click="toggleDropdown('agent')">
                      <span class="cs-trigger-content">
                        <span
                          v-if="newEvent.user_id"
                          class="cs-svc-dot"
                          :style="{ background: getAgentColorById(newEvent.user_id) }"
                        />
                        {{ selectedAgentLabel || 'Selecione' }}
                      </span>
                      <i class="i-lucide-chevron-down cs-arrow" />
                    </button>
                    <div v-if="agentOpen" class="cs-dropdown">
                      <input v-model="agentSearch" class="cs-search" placeholder="Buscar..." @click.stop />
                      <div
                        v-for="a in filteredAgents"
                        :key="a.id"
                        class="cs-option cs-option-service"
                        :class="{ selected: newEvent.user_id === a.id }"
                        @click="selectAgent(a)"
                      >
                        <span class="cs-svc-dot" :style="{ background: a.color }" />
                        <span class="cs-svc-name">{{ a.name }}</span>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Observações (Compromisso only) -->
                <div v-if="activeTab === 'appointment'" class="form-group">
                  <label class="form-label">
                    <i class="i-lucide-file-text label-icon" />
                    Observações
                  </label>
                  <textarea
                    :value="newEvent.description"
                    class="form-input"
                    rows="2"
                    placeholder="Adicione detalhes..."
                    @input="e => emitUpdate({ description: e.target.value })"
                  />
                </div>

                <!-- Data + Slot Grid -->
                <div class="border-t border-n-weak pt-5 flex flex-col gap-4">
                  <div class="form-group sm:max-w-xs">
                    <label class="form-label">
                      <i class="i-lucide-calendar label-icon" />
                      Data
                    </label>
                    <div class="flex items-center gap-2">
                      <DatePicker
                        :value="newEvent.date"
                        type="date"
                        value-type="YYYY-MM-DD"
                        format="DD/MM/YYYY"
                        :lang="ptBrLang"
                        :clearable="false"
                        :editable="false"
                        class="modal-datepicker flex-1"
                        append-to-body
                        @update:value="v => emitUpdate({ date: v })"
                      />
                      <button
                        type="button"
                        class="datepicker-today-btn"
                        :class="{ 'datepicker-today-btn--active': isDateToday }"
                        :disabled="isDateToday"
                        @click="emitUpdate({ date: todayDateStr })"
                      >
                        Hoje
                      </button>
                    </div>
                  </div>
                  <div>
                    <div class="flex items-baseline justify-between mb-2">
                      <label class="form-label !mb-0">
                        <i class="i-lucide-clock label-icon" />
                        Horário
                      </label>
                      <span class="text-sm font-semibold text-n-blue-11 tabular-nums">{{ rangeLabel }}</span>
                    </div>
                    <div class="grid grid-cols-[repeat(auto-fill,minmax(58px,1fr))] gap-1.5">
                      <button
                        v-for="slot in timeSlots"
                        :key="slot"
                        type="button"
                        class="slot-btn"
                        :class="{
                          'slot-btn--start': slot === newEvent.time_start && !slotBlockedReason(slot),
                          'slot-btn--in-range': isSlotInRange(slot) && slot !== newEvent.time_start && !slotBlockedReason(slot),
                          'slot-btn--blocked': !!slotBlockedReason(slot),
                        }"
                        :disabled="!!slotBlockedReason(slot)"
                        :title="slotBlockedReason(slot) || ''"
                        @click="selectSlot(slot)"
                      >
                        {{ slot }}
                      </button>
                    </div>
                  </div>
                </div>
              </template>
            </div>

            <!-- Footer -->
            <div
              class="flex items-center px-5 py-4 border-t border-n-weak shrink-0"
              :class="isEditing ? 'justify-between' : 'justify-end'"
            >
              <button
                v-if="isEditing"
                class="btn-secondary !text-red-400 hover:!bg-red-500/10 hover:!border-red-500/20 flex items-center gap-1.5"
                :disabled="isDeleting"
                @click="$emit('delete')"
              >
                <i class="i-lucide-trash w-4 h-4" />
                {{ isDeleting ? $t('AGENDA.MODAL.BTN_SAVING') : $t('AGENDA.MODAL.BTN_DELETE') }}
              </button>
              <div class="flex items-center gap-3">
                <button class="btn-secondary" @click="$emit('close')">
                  {{ $t('AGENDA.MODAL.BTN_CANCEL') }}
                </button>
                <button
                  class="btn-primary flex items-center gap-2"
                  :disabled="!canConfirm"
                  @click="$emit('save')"
                >
                  <i :class="activeTab === 'agenda_block' ? 'i-lucide-lock' : 'i-lucide-calendar-check'" class="w-4 h-4" />
                  {{ confirmButtonLabel }}
                </button>
              </div>
            </div>
          </div>

          <!-- ── SIDE PANEL (Quick Patient) ── -->
          <div
            class="agenda-new-event-modal bg-n-solid-1 sm:shadow-2xl border-0 sm:border border-n-weak sm:border-l-0 flex flex-col z-30 sm:z-10 overflow-hidden transition-all duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] absolute sm:relative inset-0 sm:inset-auto"
            :class="showQuickPatientModal ? 'w-full sm:w-[320px] rounded-none sm:rounded-r-2xl opacity-100' : 'w-0 sm:w-0 opacity-0 pointer-events-none'"
          >
            <div class="w-full sm:w-[320px] flex flex-col h-full">
              <div class="flex items-center justify-between px-5 border-b border-n-weak shrink-0 min-h-[60px] sm:min-h-[68px]">
                <div class="flex items-center gap-2.5">
                  <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-green-500/10 text-green-400 text-sm">
                    <i class="i-lucide-user-plus" />
                  </div>
                  <h3 class="text-sm font-semibold text-n-slate-12">
                    {{ $t('AGENDA.MODAL.ADD_NEW_PATIENT') }}
                  </h3>
                </div>
                <button
                  class="flex items-center justify-center w-7 h-7 rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors shrink-0 p-0"
                  @click="closeQuickPatientModal"
                >
                  <i class="i-lucide-x w-4 h-4" />
                </button>
              </div>
              <div class="p-5 flex-1 flex flex-col gap-4 overflow-y-auto custom-scroll">
                <div class="form-group">
                  <label class="form-label text-n-slate-10">
                    {{ $t('AGENDA.MODAL.FIELD_NAME') }}
                    <span class="text-red-400 ml-0.5">*</span>
                  </label>
                  <input v-model="quickPatient.name" type="text" class="form-input" :placeholder="$t('AGENDA.MODAL.PLACEHOLDER_NAME')" />
                </div>
                <div class="form-group">
                  <label class="form-label text-n-slate-10">
                    {{ $t('AGENDA.MODAL.FIELD_LAST_NAME') }}
                    <span class="text-slate-800 text-sm ml-1">(opcional)</span>
                  </label>
                  <input v-model="quickPatient.last_name" type="text" class="form-input" :placeholder="$t('AGENDA.MODAL.PLACEHOLDER_LAST_NAME')" />
                </div>
                <div class="form-group relative">
                  <label class="form-label text-n-slate-10">{{ $t('AGENDA.MODAL.FIELD_PHONE') }}</label>
                  <input v-model="quickPatient.phone" type="tel" class="form-input" maxlength="15" :placeholder="$t('AGENDA.MODAL.PLACEHOLDER_PHONE')" @input="formatQuickPatientPhone" @blur="quickPatientPhoneOpen = false" />
                  <div
                    v-if="quickPatientPhoneOpen && quickPatientPhoneSuggestions.length"
                    class="cs-dropdown !block absolute z-50 w-full top-full mt-1"
                  >
                    <div class="px-3 py-1.5 text-sm font-semibold text-n-slate-10 uppercase tracking-wider border-b border-n-weak">
                      Contato já existente?
                    </div>
                    <div
                      v-for="sug in quickPatientPhoneSuggestions"
                      :key="sug.id"
                      class="cs-option flex items-center justify-between"
                      @mousedown.prevent="selectPhoneSuggestion(sug)"
                    >
                      <span class="font-medium text-n-slate-12">{{ sug.name }}</span>
                      <span v-if="sug.phone" class="text-n-slate-10 text-sm">{{ sug.phone }}</span>
                    </div>
                  </div>
                </div>
              </div>
              <div class="px-5 py-4 border-t border-n-weak shrink-0 flex items-center justify-end gap-3">
                <button class="btn-secondary" @click="closeQuickPatientModal">
                  {{ $t('AGENDA.MODAL.BTN_CANCEL') }}
                </button>
                <button
                  class="btn-primary"
                  :disabled="isSubmittingPatient || !quickPatient.name"
                  @click="submitQuickPatient"
                >
                  {{ isSubmittingPatient ? ($t('AGENDA.MODAL.BTN_SAVING') || 'Salvando...') : ($t('AGENDA.MODAL.BTN_ADD') || 'Adicionar') }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </transition>
  </Teleport>
</template>
