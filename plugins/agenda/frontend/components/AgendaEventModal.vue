<script>
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import ContactAPI from 'dashboard/api/contacts';
import { EVENT_TYPES, PRIORITIES, TREATMENTS, CUSTOM_ATTR_ICONS } from '../utils/agenda-constants.js';
import { padZ, toLocalDatetimeString, createDefaultNewEvent } from '../utils/agenda-date.js';

export default {
  name: 'AgendaEventModal',
  props: {
    show: { type: Boolean, default: false },
    isEditing: { type: Boolean, default: false },
    editingEventId: { type: [Number, String], default: null },
    newEvent: { type: Object, required: true },
    customAttributesConfig: { type: Array, default: () => [] },
    agents: { type: Array, default: () => [] },
    treatmentOptions: { type: Array, default: () => TREATMENTS },
    isSaving: { type: Boolean, default: false },
    isDeleting: { type: Boolean, default: false },
  },
  emits: ['close', 'save', 'delete', 'update:newEvent'],
  data() {
    return {
      // Dropdown states
      typeOpen: false,
      typeSearch: '',
      priorityOpen: false,
      prioritySearch: '',
      treatmentOpen: false,
      treatmentSearch: '',
      contactOpen: false,
      contactSearch: '',
      titleOpen: false,

      // Patient lists
      patientList: [],
      titlePatientList: [],

      // Quick Patient Modal
      showQuickPatientModal: false,
      quickPatient: { name: '', last_name: '', phone: '' },
      isSubmittingPatient: false,
      quickPatientPhoneOpen: false,
      quickPatientPhoneSuggestions: [],
      titlePatientSource: false,

      // Debounce timers
      _titleDebounce: null,
      _contactDebounce: null,
      _phoneDebounce: null,
    };
  },
  computed: {
    selectedTypelabel() {
      const found = EVENT_TYPES.find(
        t => t.value === this.newEvent.event_type
      );
      return found
        ? found.label
        : this.$t('AGENDA.FILTER_PLACEHOLDER');
    },
    selectedPriorityLabel() {
      const found = PRIORITIES.find(
        p => p.value === this.newEvent.priority
      );
      return found
        ? found.label
        : this.$t('AGENDA.FILTER_PLACEHOLDER');
    },
    selectedContactLabel() {
      return this.newEvent.selectedPatientName || '';
    },
    filteredEventTypes() {
      const q = this.typeSearch.toLowerCase();
      return EVENT_TYPES.filter(t =>
        t.label.toLowerCase().includes(q)
      );
    },
    filteredPriorities() {
      const q = this.prioritySearch.toLowerCase();
      return PRIORITIES.filter(p =>
        p.label.toLowerCase().includes(q)
      );
    },
    filteredTreatments() {
      const q = this.treatmentSearch.toLowerCase();
      return this.treatmentOptions.filter(tr => {
        const name = typeof tr === 'string' ? tr : tr.name || '';
        return name.toLowerCase().includes(q);
      });
    },
  },
  watch: {
    show(val) {
      if (val) {
        this.fetchPatients('');
      } else {
        this.typeOpen = false;
        this.priorityOpen = false;
        this.treatmentOpen = false;
        this.contactOpen = false;
        this.titleOpen = false;
        this.quickPatientPhoneOpen = false;
        this.typeSearch = '';
        this.prioritySearch = '';
        this.treatmentSearch = '';
        this.contactSearch = '';
      }
    },
  },
  mounted() {
    document.addEventListener('click', this.handleClickOutside);
  },
  unmounted() {
    document.removeEventListener('click', this.handleClickOutside);
  },
  methods: {
    handleClickOutside(e) {
      if (!this.show) return;
      if (!e.target.closest('.custom-select') && !e.target.closest('.cs-dropdown') && !e.target.closest('.form-group.relative')) {
        this.typeOpen = false;
        this.priorityOpen = false;
        this.treatmentOpen = false;
        this.contactOpen = false;
        this.titleOpen = false;
        this.quickPatientPhoneOpen = false;
      }
    },
    padZ,
    toggleDropdown(name) {
      const keys = ['type', 'priority', 'treatment', 'contact'];
      keys.forEach(k => {
        if (k !== name) this[`${k}Open`] = false;
      });
      this[`${name}Open`] = !this[`${name}Open`];
      if (name === 'contact' && this.contactOpen) {
        this.fetchPatients(this.contactSearch);
      }
    },
    selectType(t) {
      this.emitUpdate({ event_type: t.value });
      this.typeOpen = false;
      this.typeSearch = '';
    },
    selectPriority(p) {
      this.emitUpdate({ priority: p.value });
      this.priorityOpen = false;
      this.prioritySearch = '';
    },
    selectTreatment(tr) {
      const name = typeof tr === 'string' ? tr : tr.name;
      const update = { treatment: name };
      if (tr && tr.duration_minutes) {
        const [sh, sm] = this.newEvent.time_start.split(':').map(Number);
        const startMin = sh * 60 + sm;
        const endMin = startMin + tr.duration_minutes;
        const endH = Math.floor(endMin / 60) % 24;
        const endM = endMin % 60;
        update.time_end = `${padZ(endH)}:${padZ(endM)}`;
      }
      this.emitUpdate(update);
      this.treatmentOpen = false;
      this.treatmentSearch = '';
    },
    selectContact(patient) {
      this.emitUpdate({
        contact_id: patient.contact_id || null,
        patient_id: patient.id,
        selectedPatientName: patient.name,
        selectedPatientPhone: patient.phone || '',
        selectedPatientAvatarUrl: patient.avatar_url || null,
        title: this.newEvent.title || patient.name,
      });
      this.contactOpen = false;
      this.contactSearch = '';
    },

    // Title autocomplete
    onTitleInput() {
      const q = this.newEvent.title;
      if (q.length >= 2) {
        clearTimeout(this._titleDebounce);
        this._titleDebounce = setTimeout(() => {
          this.fetchTitlePatients(q);
        }, 300);
      } else {
        this.titleOpen = false;
        this.titlePatientList = [];
      }
    },
    onTitleFocus() {
      if (this.newEvent.title.length >= 2) {
        this.fetchTitlePatients(this.newEvent.title);
      }
    },
    async fetchTitlePatients(query) {
      try {
        const response = await PatientsAPI.get(1, 'name', query, '');
        if (response.data && response.data.payload) {
          this.titlePatientList = response.data.payload.slice(0, 5);
          this.titleOpen = this.titlePatientList.length > 0;
        }
      } catch {
        // ignore
      }
    },
    selectTitlePatient(patient) {
      this.emitUpdate({ title: patient.name });
      this.selectContact(patient);
      this.titleOpen = false;
    },

    // Patients
    async fetchPatients(query = '') {
      try {
        const response = await PatientsAPI.get(1, 'name', query, '');
        if (response.data && response.data.payload) {
          this.patientList = response.data.payload;
        }
      } catch {
        // ignore
      }
    },

    // Contact search debounce
    onContactSearchInput() {
      clearTimeout(this._contactDebounce);
      this._contactDebounce = setTimeout(() => {
        this.fetchPatients(this.contactSearch);
      }, 300);
    },

    // Quick Patient
    openNewPatientModal() {
      this.titlePatientSource = false;
      this.showQuickPatientModal = true;
      this.quickPatient = { name: '', last_name: '', phone: '' };
    },
    openNewTitlePatientModal() {
      this.titlePatientSource = true;
      this.showQuickPatientModal = true;
      this.quickPatient = { name: this.newEvent.title, last_name: '', phone: '' };
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

      // Debounce phone suggestions
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
        if (this.titlePatientSource) {
          this.emitUpdate({ title: patient.name });
        }
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

    // Emit helper
    emitUpdate(partial) {
      this.$emit('update:newEvent', { ...this.newEvent, ...partial });
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
        class="agenda-new-event-modal w-full h-full sm:w-[580px] sm:h-auto bg-n-solid-1 sm:shadow-2xl border-0 sm:border border-n-weak flex flex-col z-20 transition-all duration-300"
        :class="
          showQuickPatientModal
            ? 'rounded-none sm:rounded-l-2xl sm:border-r-0'
            : 'rounded-none sm:rounded-2xl'
        "
      >
        <!-- Header -->
        <div class="flex items-center justify-between px-4 sm:px-6 border-b border-n-weak shrink-0 min-h-[64px] sm:min-h-[72px]">
          <div class="flex items-center gap-3">
            <div class="flex items-center justify-center w-8 h-8 sm:w-9 sm:h-9 rounded-xl bg-n-blue-2 text-n-blue-11 text-base">
              <i class="i-lucide-calendar-plus" />
            </div>
            <div>
              <h3 class="text-base font-semibold text-n-slate-12 leading-tight">
                {{ $t('AGENDA.MODAL.TITLE') }}
              </h3>
              <span v-if="isEditing" class="text-xs sm:text-sm text-n-slate-10 mt-0.5 block">
                {{ $t('AGENDA.MODAL.EDITING_EVENT') }} #{{ editingEventId }}
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

        <!-- Body -->
        <div class="p-4 sm:p-5 flex-1 overflow-y-auto flex flex-col gap-4">
          <!-- Título -->
          <div class="form-group relative">
            <label class="form-label">{{ $t('AGENDA.MODAL.FIELD_TITLE') }}</label>
            <input
              :value="newEvent.title"
              type="text"
              class="form-input"
              :placeholder="$t('AGENDA.MODAL.PLACEHOLDER_TITLE')"
              @input="e => { emitUpdate({ title: e.target.value }); onTitleInput(); }"
              @blur="titleOpen = false"
              @focus="onTitleFocus"
            />
            <div
              v-if="titleOpen && newEvent.title.length >= 2"
              class="cs-dropdown !block absolute z-50 w-full top-full mt-1"
            >
              <div
                class="cs-option contact-option !text-n-blue-11 hover:!bg-n-alpha-2 !flex items-center gap-2 cursor-pointer font-medium"
                @mousedown.prevent="openNewTitlePatientModal"
              >
                <i class="i-lucide-plus" />
                {{ $t('AGENDA.MODAL.ADD_PATIENT') }}
              </div>
              <div
                v-for="patient in titlePatientList"
                :key="patient.id"
                class="cs-option"
                @mousedown.prevent="selectTitlePatient(patient)"
              >
                {{ patient.name }}{{ patient.phone ? ` - ${patient.phone}` : '' }}
              </div>
              <div
                v-if="!titlePatientList.length"
                class="cs-option empty-option"
              >
                {{ $t('AGENDA.MODAL.PATIENT_NOT_FOUND') }}
              </div>
            </div>
          </div>

          <!-- Tipo + Prioridade -->
          <div class="form-row-2">
            <div class="form-group">
              <label class="form-label">
                <i class="i-lucide-tag label-icon" />
                {{ $t('AGENDA.MODAL.FIELD_TYPE') }}
              </label>
              <div class="custom-select" :class="{ open: typeOpen }">
                <button class="cs-trigger" type="button" @click="toggleDropdown('type')">
                  <span>{{ selectedTypelabel }}</span>
                  <i class="i-lucide-chevron-down cs-arrow" />
                </button>
                <div v-if="typeOpen" class="cs-dropdown">
                  <input v-model="typeSearch" class="cs-search" :placeholder="$t('AGENDA.FILTER_PLACEHOLDER')" @click.stop />
                  <div
                    v-for="t in filteredEventTypes"
                    :key="t.value"
                    class="cs-option"
                    :class="{ selected: newEvent.event_type === t.value }"
                    @click="selectType(t)"
                  >
                    {{ t.label }}
                  </div>
                </div>
              </div>
            </div>
            <div class="form-group">
              <label class="form-label">
                <i class="i-lucide-alert-circle label-icon" />
                {{ $t('AGENDA.MODAL.FIELD_PRIORITY') }}
              </label>
              <div class="custom-select" :class="{ open: priorityOpen }">
                <button class="cs-trigger" type="button" @click="toggleDropdown('priority')">
                  <span>{{ selectedPriorityLabel }}</span>
                  <i class="i-lucide-chevron-down cs-arrow" />
                </button>
                <div v-if="priorityOpen" class="cs-dropdown">
                  <input v-model="prioritySearch" class="cs-search" :placeholder="$t('AGENDA.FILTER_PLACEHOLDER')" @click.stop />
                  <div
                    v-for="p in filteredPriorities"
                    :key="p.value"
                    class="cs-option"
                    :class="{ selected: newEvent.priority === p.value }"
                    @click="selectPriority(p)"
                  >
                    {{ p.label }}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Tratamento -->
          <div class="form-group">
            <label class="form-label">
              <i class="i-lucide-activity label-icon" />
              {{ $t('AGENDA.MODAL.FIELD_TREATMENT') }}
            </label>
            <div class="custom-select" :class="{ open: treatmentOpen }">
              <button class="cs-trigger" type="button" @click="toggleDropdown('treatment')">
                <span>{{ newEvent.treatment || $t('AGENDA.MODAL.TREATMENT_PLACEHOLDER') }}</span>
                <i class="i-lucide-chevron-down cs-arrow" />
              </button>
              <div v-if="treatmentOpen" class="cs-dropdown">
                <input v-model="treatmentSearch" class="cs-search" :placeholder="$t('AGENDA.FILTER_PLACEHOLDER')" @click.stop />
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

          <!-- Custom Attributes -->
          <div v-if="customAttributesConfig && customAttributesConfig.length" class="grid grid-cols-2 gap-4">
            <div
              v-for="attr in customAttributesConfig"
              :key="attr.id"
              class="form-group"
              :class="attr.type === 'textarea' ? 'col-span-2' : ''"
            >
              <label class="form-label">
                <i :class="getTypeIcon(attr.type)" class="label-icon" />
                {{ attr.name }}
                <span v-if="attr.required" class="text-red-400 ml-0.5">{{ ' *' }}</span>
              </label>
              <select
                v-if="attr.type === 'select'"
                :value="newEvent.custom_values[`attr_${attr.id}`]"
                class="form-input form-select"
                @change="e => emitUpdate({ custom_values: { ...newEvent.custom_values, [`attr_${attr.id}`]: e.target.value } })"
              >
                <option value="" disabled>{{ $t('AGENDA.FILTER_PLACEHOLDER') }}</option>
                <option v-for="opt in getOptions(attr.options)" :key="opt" :value="opt">{{ opt }}</option>
              </select>
              <div v-else-if="attr.type === 'cpf'">
                <input
                  :value="newEvent.custom_values[`attr_${attr.id}`]"
                  type="text"
                  class="form-input"
                  :class="{ 'error-input': !isDynamicCpfValid(attr) }"
                  placeholder="000.000.000-00"
                  maxlength="14"
                  @input="e => formatDynamicCpfInput(e, `attr_${attr.id}`)"
                />
                <span v-if="!isDynamicCpfValid(attr)" class="error-msg">CPF inválido</span>
              </div>
              <textarea
                v-else-if="attr.type === 'textarea'"
                :value="newEvent.custom_values[`attr_${attr.id}`]"
                class="form-input"
                rows="3"
                @input="e => emitUpdate({ custom_values: { ...newEvent.custom_values, [`attr_${attr.id}`]: e.target.value } })"
              />
              <input
                v-else
                :value="newEvent.custom_values[`attr_${attr.id}`]"
                type="text"
                class="form-input"
                @input="e => emitUpdate({ custom_values: { ...newEvent.custom_values, [`attr_${attr.id}`]: e.target.value } })"
              />
            </div>
          </div>

          <!-- Observações (Descrição do Evento) -->
          <div class="form-group mb-4">
            <label class="form-label">
              <i class="i-lucide-file-text label-icon" />
              {{ $t('AGENDA.MODAL.FIELD_OBSERVATIONS') || 'Observações' }}
            </label>
            <textarea
              :value="newEvent.description"
              class="form-input"
              rows="3"
              placeholder="Adicione notas, sintomas, instruções..."
              @input="e => emitUpdate({ description: e.target.value })"
            />
          </div>

          <!-- Data + Horário -->
          <div class="form-row-3">
            <div class="form-group">
              <label class="form-label">
                <i class="i-lucide-calendar label-icon" />
                {{ $t('AGENDA.MODAL.FIELD_DATE') }}
              </label>
              <input :value="newEvent.date" type="date" class="form-input" @input="e => emitUpdate({ date: e.target.value })" />
            </div>
            <div class="form-group">
              <label class="form-label">
                <i class="i-lucide-clock label-icon" />
                {{ $t('AGENDA.MODAL.FIELD_START') }}
              </label>
              <input :value="newEvent.time_start" type="time" class="form-input" @input="e => emitUpdate({ time_start: e.target.value })" />
            </div>
            <div class="form-group">
              <label class="form-label">
                <i class="i-lucide-clock label-icon" />
                {{ $t('AGENDA.MODAL.FIELD_END') }}
              </label>
              <input :value="newEvent.time_end" type="time" class="form-input" @input="e => emitUpdate({ time_end: e.target.value })" />
            </div>
          </div>

          <!-- Agente -->
          <div class="form-group">
            <label class="form-label">
              <i class="i-lucide-user label-icon" />
              {{ $t('AGENDA.MODAL.FIELD_AGENT') }}
            </label>
            <select :value="newEvent.user_id" class="form-input form-select" @change="e => emitUpdate({ user_id: Number(e.target.value) })">
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
            </select>
          </div>

          <!-- Contato / Paciente -->
          <div class="form-group">
            <label class="form-label">
              <i class="i-lucide-user-circle label-icon" />
              {{ $t('AGENDA.MODAL.FIELD_CONTACT') }}
            </label>
            <div class="custom-select select-upwards" :class="{ open: contactOpen }">
              <button class="cs-trigger" type="button" @click="toggleDropdown('contact')">
                <span>{{ selectedContactLabel || $t('AGENDA.MODAL.CONTACT_PLACEHOLDER') }}</span>
                <i class="i-lucide-chevron-down cs-arrow" />
              </button>
              <div v-if="contactOpen" class="cs-dropdown">
                <input v-model="contactSearch" class="cs-search" :placeholder="$t('AGENDA.MODAL.CONTACT_SEARCH_PLACEHOLDER')" @click.stop @input="onContactSearchInput" />
                <div
                  class="cs-option contact-option !text-n-blue-11 hover:!bg-n-alpha-2 !flex items-center gap-2 cursor-pointer font-medium"
                  @click.stop="openNewPatientModal"
                >
                  <i class="i-lucide-plus" />
                  {{ $t('AGENDA.MODAL.ADD_PATIENT') }}
                </div>
                <div
                  v-for="patient in patientList"
                  :key="patient.id"
                  class="cs-option"
                  :class="{ selected: newEvent.patient_id === patient.id }"
                  @click="selectContact(patient)"
                >
                  {{ patient.name }}{{ patient.phone ? ` - ${patient.phone}` : '' }}
                </div>
                <div v-if="!patientList.length" class="cs-option empty-option">
                  {{ $t('AGENDA.MODAL.PATIENT_NOT_FOUND') }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div
          class="flex items-center px-5 py-4 border-t border-n-weak"
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
              :disabled="isSaving || !newEvent.title"
              @click="$emit('save')"
            >
              <i class="i-lucide-calendar-check w-4 h-4" />
              {{ isSaving ? $t('AGENDA.MODAL.BTN_SAVING') : isEditing ? $t('AGENDA.MODAL.BTN_SAVE') : $t('AGENDA.MODAL.BTN_SCHEDULE') }}
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
          <div class="flex items-center justify-between px-5 border-b border-n-weak shrink-0 min-h-[64px] sm:min-h-[72px]">
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
