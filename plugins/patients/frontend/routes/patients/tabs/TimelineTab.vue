<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-6">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Timeline do Paciente
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Visão consolidada de todas as interações, prontuários e movimentações.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-xs text-slate-500">
          {{ filteredTimelineEvents.length }} evento{{
            filteredTimelineEvents.length !== 1 ? 's' : ''
          }}
        </span>
        <!-- Filtro de ordenação -->
        <div class="relative">
          <button
            class="btn-secondary flex items-center gap-2"
            @click="timelineFilterOpen = !timelineFilterOpen"
          >
            <i class="i-lucide-arrow-up-down w-3.5 h-3.5" />
            {{
              timelineSortOrder === 'oldest' ? 'Mais antigo' : 'Mais recente'
            }}
          </button>
          <div v-if="timelineFilterOpen" class="tl-sort-dropdown" @click.stop>
            <button
              v-for="sort in [
                {
                  value: 'newest',
                  label: 'Mais recente primeiro',
                  icon: 'i-lucide-arrow-down-narrow-wide',
                },
                {
                  value: 'oldest',
                  label: 'Mais antigo primeiro',
                  icon: 'i-lucide-arrow-up-narrow-wide',
                },
              ]"
              :key="sort.value"
              class="tl-sort-option"
              :class="{
                'tl-sort-option--active': timelineSortOrder === sort.value,
              }"
              @click="
                timelineSortOrder = sort.value;
                timelineFilterOpen = false;
              "
            >
              <i :class="sort.icon" class="w-3.5 h-3.5" />
              {{ sort.label }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Filtros de categoria (pills) -->
    <div class="tl-filter-row mb-6">
      <button
        v-for="chip in [
          { value: 'all', label: 'Tudo', icon: 'i-lucide-layers' },
          {
            value: 'appointments',
            label: 'Consultas',
            icon: 'i-lucide-calendar',
          },
          {
            value: 'clinical',
            label: 'Clínico',
            icon: 'i-lucide-stethoscope',
          },
          {
            value: 'financial',
            label: 'Financeiro',
            icon: 'i-lucide-circle-dollar-sign',
          },
          {
            value: 'documents',
            label: 'Documentos',
            icon: 'i-lucide-file-text',
          },
        ]"
        :key="chip.value"
        class="tl-filter-btn"
        :class="{
          'tl-filter-btn--active': timelineFilter === chip.value,
        }"
        @click="timelineFilter = chip.value"
      >
        <i :class="chip.icon" class="w-3.5 h-3.5" />
        {{ chip.label }}
      </button>
    </div>

    <!-- Loading -->
    <div
      v-if="timelineLoading"
      class="flex items-center justify-center py-20 gap-3 text-slate-400"
    >
      <i class="i-lucide-loader-2 animate-spin text-woot-400 text-xl" />
      <span>Carregando timeline...</span>
    </div>

    <!-- Empty state -->
    <div
      v-else-if="!timelineLoading && filteredTimelineEvents.length === 0"
      class="tl-empty"
    >
      <div class="tl-empty-icon">
        <i class="i-lucide-clock-x w-6 h-6" />
      </div>
      <p class="tl-empty-title">Nenhum evento encontrado</p>
      <p class="tl-empty-hint">
        {{
          timelineFilter !== 'all'
            ? 'Tente remover os filtros aplicados.'
            : 'As interações com o paciente aparecerão aqui.'
        }}
      </p>
      <button
        v-if="timelineFilter !== 'all'"
        class="btn-secondary mt-1"
        @click="timelineFilter = 'all'"
      >
        Limpar filtros
      </button>
    </div>

    <!-- Timeline agrupada por data -->
    <div v-else class="tl-timeline">
      <div
        v-for="group in groupedTimelineEvents"
        :key="group.date"
        class="tl-group"
      >
        <!-- Separador de data -->
        <div class="tl-date-divider">
          <div class="tl-date-line" />
          <span class="tl-date-label">{{ group.date }}</span>
          <div class="tl-date-line" />
        </div>

        <!-- Eventos do grupo -->
        <div class="tl-events">
          <!-- Linha vertical contínua -->
          <div class="tl-vline" />

          <div
            v-for="event in group.events"
            :key="event.id"
            class="tl-event-row"
          >
            <!-- Ícone circular do evento -->
            <div class="tl-event-icon" :class="tlIconCls(event.event_type)">
              <i
                :class="timelineEventConfig(event.event_type).icon"
                class="w-4 h-4"
              />
            </div>

            <!-- Card do evento -->
            <div class="tl-event-card">
              <!-- Cabeçalho: badge tipo + hora -->
              <div class="tl-event-header">
                <span
                  class="tl-event-badge"
                  :class="tlBadgeCls(event.event_type)"
                >
                  {{ timelineEventConfig(event.event_type).label }}
                </span>
                <span class="tl-event-time">{{
                  formatTime(event.occurred_at)
                }}</span>
              </div>

              <!-- Título -->
              <p class="tl-event-title">{{ event.label }}</p>

              <!-- Metadados -->
              <div
                v-if="event.metadata && Object.keys(event.metadata).length > 0"
                class="tl-event-meta"
              >
                <template v-for="(val, key) in event.metadata" :key="key">
                  <div
                    v-if="val && key !== 'account_id' && key !== 'patient_id'"
                    class="tl-meta-item"
                  >
                    <span class="tl-meta-key">{{
                      key.replace(/_/g, ' ')
                    }}</span>
                    <span class="tl-meta-val">{{
                      typeof val === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(val)
                        ? new Date(val)
                            .toLocaleString('pt-BR', {
                              day: '2-digit',
                              month: '2-digit',
                              year: 'numeric',
                              hour: '2-digit',
                              minute: '2-digit',
                              timeZone: BRT,
                            })
                            .replace(',', ' às')
                        : val
                    }}</span>
                  </div>
                </template>
              </div>

              <!-- Actor -->
              <div v-if="event.actor_name" class="tl-event-actor">
                <i class="i-lucide-user-round w-3 h-3" />
                <span>{{ event.actor_name }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Marcador de início do histórico -->
      <div class="tl-history-end">
        <div class="tl-history-line" />
        <div class="tl-history-dot" />
        <span class="tl-history-label">Início do histórico</span>
        <div class="tl-history-line" />
      </div>
    </div>
  </div>
</template>
