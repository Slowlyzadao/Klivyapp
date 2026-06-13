<script>
import { DELETE_REASONS } from '../utils/agenda-constants.js';

export default {
  name: 'AgendaDeleteModal',
  props: {
    show: { type: Boolean, default: false },
    isDeleting: { type: Boolean, default: false },
  },
  emits: ['cancel', 'confirm'],
  data() {
    return {
      deleteReason: '',
      deleteReasonNote: '',
    };
  },
  computed: {
    deleteReasonOptions() {
      return DELETE_REASONS;
    },
    // Quando o motivo é "outro", a nota é obrigatória — o backend recusa
    // (422) sem ela, então também travamos no client pra UX consistente.
    isConfirmDisabled() {
      if (!this.deleteReason) return true;
      if (this.deleteReason === 'outro' && !this.deleteReasonNote.trim()) {
        return true;
      }
      return false;
    },
  },
  watch: {
    show(newVal) {
      if (newVal) {
        this.deleteReason = '';
        this.deleteReasonNote = '';
      }
    },
  },
  methods: {
    cancel() {
      this.deleteReason = '';
      this.deleteReasonNote = '';
      this.$emit('cancel');
    },
    confirm() {
      this.$emit('confirm', {
        reason: this.deleteReason,
        note: this.deleteReasonNote,
      });
    },
  },
};
</script>

<template>
  <Teleport to="body">
    <transition
      enter-active-class="transition duration-300 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition duration-200 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div v-if="show" class="fixed inset-0 z-[100000] overflow-y-auto" role="dialog" aria-modal="true">
        <!-- Backdrop -->
        <div class="fixed inset-0 bg-slate-900/60 transition-opacity backdrop-filter blur-sm" @click="cancel" />

        <!-- Modal Position Wrapper -->
        <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
          <transition
            appear
            enter-active-class="transition duration-300 ease-out"
            enter-from-class="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
            enter-to-class="opacity-100 translate-y-0 sm:scale-100"
            leave-active-class="transition duration-200 ease-in"
            leave-from-class="opacity-100 translate-y-0 sm:scale-100"
            leave-to-class="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
          >
            <div class="relative transform overflow-hidden rounded-2xl bg-white dark:bg-slate-800 text-left shadow-2xl transition-all sm:my-8 sm:w-full sm:max-w-md ring-1 ring-black/5 dark:ring-white/10">
              <div class="bg-white dark:bg-slate-800 px-6 pt-6 pb-4 sm:p-7 sm:pb-5">
                <div class="sm:flex sm:items-start">
                  <div class="mx-auto flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-red-500/10 sm:mx-0 sm:h-11 sm:w-11">
                    <i class="i-lucide-alert-triangle text-red-500 text-xl" />
                  </div>
                  <div class="mt-4 text-center sm:mt-0 sm:ml-5 sm:text-left">
                    <h3 class="text-xl font-bold text-slate-900 dark:text-white leading-tight">Excluir Agendamento</h3>
                    <div class="mt-2 text-sm text-slate-500 dark:text-slate-400 leading-relaxed font-medium">
                      Tem certeza que deseja excluir este agendamento? Esta ação removerá o horário da agenda permanentemente.
                    </div>
                  </div>
                </div>

                <!-- Reasons Form -->
                <div class="mt-6">
                  <p class="text-[11px] font-bold text-slate-400 dark:text-slate-500 uppercase tracking-widest mb-3">Selecione o Motivo</p>
                  <div class="grid grid-cols-1 gap-2.5">
                    <button
                      v-for="opt in deleteReasonOptions"
                      :key="opt.value"
                      @click="deleteReason = opt.value"
                      class="flex items-center gap-3 p-3.5 rounded-xl border-2 transition-all text-sm font-semibold text-left"
                      :class="deleteReason === opt.value 
                        ? 'border-red-500 bg-red-50 dark:bg-red-500/10 text-red-600 dark:text-red-400' 
                        : 'border-slate-200 dark:border-white/5 bg-slate-50 dark:bg-white/5 text-slate-600 dark:text-slate-400 hover:border-slate-300 dark:hover:border-white/10 hover:bg-slate-100 dark:hover:bg-white/10'"
                    >
                      <div class="size-4 rounded-full border-2 flex items-center justify-center flex-shrink-0" :class="deleteReason === opt.value ? 'border-red-500 bg-white dark:bg-transparent' : 'border-slate-300 dark:border-slate-600 bg-white dark:bg-transparent'">
                        <div v-if="deleteReason === opt.value" class="size-2 rounded-full bg-red-500" />
                      </div>
                      {{ opt.label }}
                    </button>
                  </div>

                  <div v-if="deleteReason === 'outro'" class="mt-3 animate-in fade-in slide-in-from-top-2">
                    <textarea
                      v-model="deleteReasonNote"
                      rows="3"
                      placeholder="Descreva o motivo adicional..."
                      class="w-full rounded-xl border-2 border-slate-200 dark:border-white/5 bg-slate-50 dark:bg-white/5 p-3 text-sm font-semibold text-slate-700 dark:text-slate-200 outline-none focus:border-red-500/50 focus:bg-white dark:focus:bg-white/10 transition-all resize-none"
                    />
                    <p
                      v-if="!deleteReasonNote.trim()"
                      class="mt-2 text-xs font-semibold text-red-600 dark:text-red-400"
                    >
                      <i class="i-lucide-info inline-block w-3 h-3 mr-1 align-middle" />
                      Justificativa é obrigatória ao escolher "Outro motivo".
                    </p>
                  </div>
                </div>
              </div>

              <!-- Footer Buttons -->
              <div class="bg-slate-50 dark:bg-slate-900/40 px-6 py-4 sm:flex sm:flex-row-reverse sm:gap-3 sm:px-7">
                <button
                  type="button"
                  :disabled="isDeleting || isConfirmDisabled"
                  @click="confirm"
                  class="inline-flex w-full justify-center rounded-xl bg-red-600 px-5 py-3 text-sm font-bold text-white shadow-lg shadow-red-900/20 hover:bg-red-500 active:scale-95 disabled:opacity-50 disabled:active:scale-100 transition-all sm:w-auto"
                >
                  <i v-if="isDeleting" class="i-lucide-loader-2 animate-spin mr-2" />
                  {{ isDeleting ? 'Excluindo...' : 'Sim, Excluir' }}
                </button>
                <button
                  type="button"
                  @click="cancel"
                  class="mt-3 inline-flex w-full justify-center rounded-xl bg-slate-200 dark:bg-white/10 px-5 py-3 text-sm font-bold text-slate-700 dark:text-white hover:bg-slate-300 dark:hover:bg-white/20 active:scale-95 transition-all sm:mt-0 sm:w-auto"
                >
                  Cancelar
                </button>
              </div>
            </div>
          </transition>
        </div>
      </div>
    </transition>
  </Teleport>
</template>

<style scoped>
/* Transições baseadas em classes Tailwind, nenhum CSS extra necessário */
</style>
