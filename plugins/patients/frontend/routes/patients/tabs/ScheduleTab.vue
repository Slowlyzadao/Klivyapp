<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-6">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">Agenda e Histórico</h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Acompanhamento completo de agendamentos, faltas e retornos do
          paciente.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <button
          class="btn-secondary flex items-center gap-2"
          @click="navigateToAgendaWithPatient"
        >
          <i class="i-lucide-calendar w-4 h-4" /> Ver na Agenda
        </button>
        <button
          class="btn-primary bg-woot-600 hover:bg-woot-500 text-white flex items-center gap-2"
          @click="navigateToAgendaWithPatient"
        >
          <i class="i-lucide-calendar-plus w-4 h-4" /> Novo Agendamento
        </button>
      </div>
    </div>

    <!-- KPIs -->
    <div class="sched-kpi-grid mb-6">
      <!-- Total -->
      <div class="sched-kpi-card">
        <div class="sched-kpi-icon">
          <i class="i-lucide-calendar-days w-4 h-4" />
        </div>
        <p class="sched-kpi-label">Total</p>
        <p class="sched-kpi-value">{{ aptKPIs.total }}</p>
      </div>
      <!-- Realizados -->
      <div class="sched-kpi-card sched-kpi-card--green">
        <div class="sched-kpi-icon sched-kpi-icon--green">
          <i class="i-lucide-check-circle-2 w-4 h-4" />
        </div>
        <p class="sched-kpi-label">Realizados</p>
        <p class="sched-kpi-value">{{ aptKPIs.done }}</p>
      </div>
      <!-- Próximos -->
      <div class="sched-kpi-card sched-kpi-card--blue">
        <div class="sched-kpi-icon sched-kpi-icon--blue">
          <i class="i-lucide-clock w-4 h-4" />
        </div>
        <p class="sched-kpi-label">Próximos</p>
        <p class="sched-kpi-value">{{ aptKPIs.upcoming }}</p>
      </div>
      <!-- Faltas -->
      <div class="sched-kpi-card sched-kpi-card--red">
        <div class="sched-kpi-icon sched-kpi-icon--red">
          <i class="i-lucide-user-x w-4 h-4" />
        </div>
        <p class="sched-kpi-label">Faltas</p>
        <p class="sched-kpi-value">{{ aptKPIs.noShows }}</p>
      </div>
    </div>

    <!-- Filtros pill -->
    <div class="sched-filter-row mb-6">
      <button
        class="sched-filter-btn"
        :class="{
          'sched-filter-btn--active': appointmentFilter === 'all',
        }"
        @click="appointmentFilter = 'all'"
      >
        <i class="i-lucide-layout-grid w-3.5 h-3.5" /> Todos
      </button>
      <button
        class="sched-filter-btn"
        :class="{
          'sched-filter-btn--active': appointmentFilter === 'upcoming',
        }"
        @click="appointmentFilter = 'upcoming'"
      >
        <i class="i-lucide-calendar-clock w-3.5 h-3.5" /> Próximos
      </button>
      <button
        class="sched-filter-btn"
        :class="{
          'sched-filter-btn--active': appointmentFilter === 'issues',
        }"
        @click="appointmentFilter = 'issues'"
      >
        <i class="i-lucide-octagon-alert w-3.5 h-3.5" />
        Faltas/Cancelados
        <span v-if="issuesCount > 0" class="sched-filter-badge">{{
          issuesCount
        }}</span>
      </button>
    </div>

    <!-- Alerta de Retorno Pendente -->
    <div v-if="pendingRecallAppointment" class="sched-recall-alert mb-6">
      <div class="sched-recall-icon">
        <i class="i-lucide-bell-ring w-4 h-4" />
      </div>
      <div class="sched-recall-body">
        <h4 class="sched-recall-title">
          <i class="i-lucide-triangle-alert w-3 h-3" />
          Retorno Pendente — Paciente Faltou
        </h4>
        <p class="sched-recall-desc">
          O paciente não compareceu à consulta de
          <strong>{{
            APPOINTMENT_TYPE_LABELS[pendingRecallAppointment.appointment_type]
          }}</strong>
          agendada para
          <strong
            >{{ formatDate(pendingRecallAppointment.scheduled_at) }} às
            {{ formatTime(pendingRecallAppointment.scheduled_at) }}</strong
          >. Nenhum lembrete foi enviado ainda.
        </p>
        <div class="flex items-center gap-2">
          <button
            class="sched-recall-btn"
            :disabled="recallLoading"
            @click="sendRecallWhatsApp(pendingRecallAppointment.id)"
          >
            <i
              v-if="recallLoading"
              class="i-lucide-loader-2 animate-spin w-3 h-3"
            />
            <i v-else class="i-lucide-message-circle w-3 h-3" />
            Lembrar via WhatsApp
          </button>
          <button
            class="sched-recall-btn-ghost"
            @click="openRescheduleFromRecall(pendingRecallAppointment)"
          >
            <i class="i-lucide-calendar-arrow-up w-3 h-3" />
            Reagendar Manualmente
          </button>
        </div>
      </div>
      <div class="sched-recall-dismiss">
        <button class="sched-dismiss-text" @click="dismissRecallForever">
          Não mostrar mais
        </button>
        <button
          class="sched-dismiss-x"
          title="Fechar lembrete"
          @click="dismissRecallSession"
        >
          <i class="i-lucide-x w-5 h-5" />
        </button>
      </div>
    </div>

    <!-- Loading -->
    <div
      v-if="appointmentsLoading"
      class="flex items-center justify-center py-16 gap-3 text-slate-400"
    >
      <i class="i-lucide-loader-2 animate-spin text-woot-400 text-xl" />
      <span>Carregando agendamentos...</span>
    </div>

    <!-- Empty State -->
    <div
      v-else-if="!appointmentsLoading && filteredAppointments.length === 0"
      class="sched-empty"
    >
      <div class="sched-empty-icon">
        <i class="i-lucide-calendar-off w-7 h-7" />
      </div>
      <p class="sched-empty-title">Nenhum agendamento encontrado</p>
      <p class="sched-empty-hint">
        {{
          appointmentFilter === 'all'
            ? 'Este paciente ainda não tem consultas registradas.'
            : 'Nenhum registro neste filtro.'
        }}
      </p>
      <button
        class="btn-primary mt-2 flex items-center gap-2"
        @click="navigateToAgendaWithPatient"
      >
        <i class="i-lucide-calendar-plus" /> Agendar Primeira Consulta
      </button>
    </div>

    <!-- Lista de Agendamentos -->
    <div v-else class="sched-timeline">
      <!-- Linha vertical -->
      <div class="sched-timeline-line" />

      <div
        v-for="apt in filteredAppointments"
        :key="apt.id"
        class="sched-apt-item"
      >
        <!-- Dot na linha do tempo -->
        <div
          class="sched-apt-dot"
          :class="{
            'sched-apt-dot--noshow':
              apt.status === 'no_show' || apt.status === 'canceled',
            'sched-apt-dot--scheduled': [
              'scheduled',
              'confirmed',
              'rescheduled',
            ].includes(apt.status),
            'sched-apt-dot--done':
              apt.status === 'done' || apt.status === 'completed',
          }"
        />

        <!-- Card de Agendamento -->
        <div class="sched-apt-card">
          <!-- Topo: badges + data -->
          <div class="sched-apt-header">
            <div class="sched-apt-badges">
              <!-- Status -->
              <span
                class="sched-status-badge"
                :class="aptStatusCfg(apt.status).badgeCls"
              >
                <i class="w-3 h-3" :class="aptStatusCfg(apt.status).icon" />
                {{ aptStatusCfg(apt.status).label }}
              </span>
              <!-- Tipo -->
              <span
                v-if="
                  EVENT_TYPE_LABELS[apt.event_type_label] ||
                  EVENT_TYPE_LABELS[apt.appointment_type]
                "
                class="sched-type-badge"
              >
                {{
                  EVENT_TYPE_LABELS[apt.event_type_label] ||
                  EVENT_TYPE_LABELS[apt.appointment_type] ||
                  '—'
                }}
              </span>
              <!-- Prioridade -->
              <span
                v-if="apt.priority"
                class="sched-priority-badge"
                :class="priorityCfg(apt.priority).cls"
              >
                {{ priorityCfg(apt.priority).text }}
                {{ priorityCfg(apt.priority).label }}
              </span>
              <!-- PRÓXIMA -->
              <span
                v-if="
                  apt.id === nextAppointmentId &&
                  !['canceled', 'no_show'].includes(apt.status)
                "
                class="sched-next-badge"
              >
                <i class="i-lucide-sparkles w-2.5 h-2.5" /> PRÓXIMA
              </span>
            </div>

            <!-- Data/Hora -->
            <div class="sched-apt-datetime">
              <p class="sched-apt-date">
                {{ formatDate(apt.scheduled_at) }}
              </p>
              <p class="sched-apt-time">
                {{ formatTime(apt.scheduled_at) }} ·
                {{ apt.duration_minutes || 60 }}min
              </p>
            </div>
          </div>

          <!-- Conteúdo: info em grid -->
          <div class="sched-apt-info">
            <!-- Profissional -->
            <div class="sched-info-col">
              <p class="sched-info-label">Profissional Responsável</p>
              <div class="flex items-center gap-2">
                <i class="i-lucide-user w-3.5 h-3.5 text-slate-500" />
                <span
                  v-if="apt.professional?.name || apt.professional_name"
                  class="sched-info-value"
                >
                  {{ apt.professional?.name || apt.professional_name }}
                </span>
                <span v-else class="sched-info-empty">Não informado</span>
              </div>
            </div>
            <!-- Tratamento -->
            <div v-if="apt.treatment" class="sched-info-col">
              <p class="sched-info-label">Tratamento</p>
              <div class="flex items-center gap-2">
                <i class="i-lucide-activity w-3.5 h-3.5 text-slate-500" />
                <span class="sched-info-value">{{ apt.treatment }}</span>
              </div>
            </div>
          </div>

          <!-- Motivo Reagendamento -->
          <div
            v-if="apt.reschedule_reason"
            class="sched-reason sched-reason--amber"
          >
            <i class="i-lucide-info w-3.5 h-3.5 mt-0.5 shrink-0" />
            <span
              ><strong>Motivo Reagendamento:</strong>
              {{ apt.reschedule_reason }}</span
            >
          </div>

          <!-- Motivo Cancelamento -->
          <div
            v-if="apt.cancellation_reason"
            class="sched-reason sched-reason--red"
          >
            <i class="i-lucide-circle-slash w-3.5 h-3.5 mt-0.5 shrink-0" />
            <span
              ><strong>Motivo Cancelamento:</strong>
              {{ apt.cancellation_reason }}</span
            >
          </div>

          <!-- Observações -->
          <div v-if="apt.notes" class="sched-notes">"{{ apt.notes }}"</div>

          <!-- Ações (footer do card) -->
          <div
            v-if="
              apt.cancellable || apt.reschedulable || apt.status === 'no_show'
            "
            class="sched-apt-actions"
          >
            <button
              v-if="apt.status === 'no_show' && !apt.recall_sent"
              class="sched-action-btn sched-action-btn--amber"
              :disabled="recallLoading"
              @click="sendRecallWhatsApp(apt.id)"
            >
              <i
                v-if="recallLoading"
                class="i-lucide-loader-2 animate-spin w-3.5 h-3.5"
              />
              <i v-else class="i-lucide-message-circle w-3.5 h-3.5" />
              Notificar WhatsApp
            </button>
            <button
              v-if="apt.reschedulable || apt.status === 'no_show'"
              class="sched-action-btn"
              @click="
                apt.status === 'no_show'
                  ? navigateToAgendaWithPatient()
                  : openRescheduleModal(apt)
              "
            >
              <i class="i-lucide-calendar-clock w-3.5 h-3.5" />
              Reagendar Agora
            </button>
            <button
              v-if="apt.cancellable"
              class="sched-action-btn sched-action-btn--danger"
              @click="openNoShowModal(apt)"
            >
              <i class="i-lucide-user-minus w-3.5 h-3.5" />
              Marcar Falta
            </button>
          </div>
        </div>
      </div>

      <!-- Fim da linha do tempo -->
      <div v-if="filteredAppointments.length > 0" class="sched-timeline-end">
        <div class="sched-timeline-end-line" />
        <span class="sched-timeline-end-label">Início do histórico</span>
        <div class="sched-timeline-end-line" />
      </div>
    </div>

    <!-- Modal: Reagendar -->
    <div
      v-if="showRescheduleModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      @click.self="showRescheduleModal = false"
    >
      <div
        class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
      >
        <div
          class="flex items-center justify-between p-6 border-b border-slate-700/50"
        >
          <div>
            <h3
              class="text-lg font-semibold text-slate-100 flex items-center gap-2"
            >
              <i class="i-lucide-calendar-arrow-up text-orange-400" />
              Reagendar Consulta
            </h3>
            <p class="text-xs text-slate-400 mt-0.5">
              Selecione a nova data e horário
            </p>
          </div>
          <button
            class="text-slate-400 hover:text-slate-100"
            @click="showRescheduleModal = false"
          >
            <i class="i-lucide-x text-xl" />
          </button>
        </div>
        <div class="p-6 space-y-4">
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Nova Data e Hora *</label
            >
            <input
              v-model="rescheduleForm.new_scheduled_at"
              type="datetime-local"
              class="form-input w-full"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Duração (minutos)</label
            >
            <input
              v-model="rescheduleForm.duration_minutes"
              type="number"
              min="15"
              max="480"
              step="15"
              class="form-input w-full"
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Motivo do Reagendamento</label
            >
            <input
              v-model="rescheduleForm.reschedule_reason"
              type="text"
              placeholder="Ex: Solicitação do paciente..."
              class="form-input w-full"
            />
          </div>
        </div>
        <div class="p-6 border-t border-slate-700/50 flex justify-end gap-3">
          <button class="btn-secondary" @click="showRescheduleModal = false">
            Cancelar
          </button>
          <button
            class="bg-orange-600 hover:bg-orange-500 text-white font-medium py-2 px-4 rounded-xl transition-colors flex items-center gap-2 disabled:opacity-50"
            :disabled="rescheduleLoading || !rescheduleForm.new_scheduled_at"
            @click="handleReschedule"
          >
            <i
              v-if="rescheduleLoading"
              class="i-lucide-loader-2 animate-spin"
            />
            <i v-else class="i-lucide-calendar-check" />
            Confirmar Reagendamento
          </button>
        </div>
      </div>
    </div>

    <!-- Modal: Confirmar Falta -->
    <div
      v-if="showNoShowModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      @click.self="showNoShowModal = false"
    >
      <div
        class="bg-slate-900 border border-slate-700 rounded-xl w-full max-w-sm"
      >
        <!-- Header -->
        <div
          class="flex items-center justify-between p-5 border-b border-slate-700/50"
        >
          <div class="flex items-center gap-3">
            <i class="i-lucide-user-minus text-red-400 text-lg" />
            <div>
              <h3 class="text-base font-semibold text-slate-100">
                Registrar Falta
              </h3>
              <p class="text-xs text-slate-400 mt-0.5">
                Esta ação não pode ser desfeita
              </p>
            </div>
          </div>
          <button
            class="text-slate-500 hover:text-slate-200 transition-colors"
            @click="showNoShowModal = false"
          >
            <i class="i-lucide-x text-lg" />
          </button>
        </div>

        <!-- Body -->
        <div class="p-5">
          <p class="text-sm text-slate-400">
            O status será alterado para
            <span class="font-semibold text-red-400">Falta</span>
            e o contador de faltas do paciente será incrementado.
          </p>
        </div>

        <!-- Footer -->
        <div class="p-5 border-t border-slate-700/50 flex justify-end gap-3">
          <button class="btn-secondary" @click="showNoShowModal = false">
            Cancelar
          </button>
          <button
            class="btn-primary bg-red-600 hover:bg-red-500 text-white flex items-center gap-2 disabled:opacity-50"
            :disabled="noShowLoading"
            @click="handleNoShow"
          >
            <i v-if="noShowLoading" class="i-lucide-loader-2 animate-spin" />
            <i v-else class="i-lucide-user-minus" />
            Confirmar Falta
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
