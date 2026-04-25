<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-6">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Auditoria e Segurança
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Rastreabilidade com valor legal de todos os acessos, edições e
          assinaturas no prontuário.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <button
          class="btn-secondary flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="isExportingPdf"
          @click="exportPdf"
        >
          <i
            v-if="isExportingPdf"
            class="i-lucide-loader-2 animate-spin w-3.5 h-3.5"
          />
          <i v-else class="i-lucide-download w-3.5 h-3.5" />
          {{ isExportingPdf ? 'Gerando PDF...' : 'Exportar Prontuário PDF' }}
        </button>
      </div>
    </div>

    <!-- Barra de filtros -->
    <div class="aud-filter-bar mb-5">
      <div class="aud-filter-field">
        <label class="aud-filter-label">Tipo de Ação</label>
        <select v-model="auditFilters.action_type" class="form-input text-sm">
          <option
            v-for="opt in AUDIT_ACTION_OPTIONS"
            :key="opt.value"
            :value="opt.value"
          >
            {{ opt.label }}
          </option>
        </select>
      </div>
      <div class="aud-filter-field">
        <label class="aud-filter-label">Data Início</label>
        <input
          v-model="auditFilters.start_date"
          type="date"
          class="form-input text-sm"
        />
      </div>
      <div class="aud-filter-field">
        <label class="aud-filter-label">Data Fim</label>
        <input
          v-model="auditFilters.end_date"
          type="date"
          class="form-input text-sm"
        />
      </div>
      <div class="aud-filter-actions">
        <button
          class="btn-primary flex items-center gap-1.5"
          @click="applyAuditFilters"
        >
          <i class="i-lucide-filter w-3.5 h-3.5" /> Filtrar
        </button>
        <button
          class="btn-secondary aud-clear-btn"
          title="Limpar filtros"
          @click="clearAuditFilters"
        >
          <i class="i-lucide-x w-4 h-4" />
        </button>
      </div>
    </div>

    <!-- Tabela de Logs -->
    <div class="aud-table-wrap">
      <!-- Loading -->
      <div v-if="isAuditLoading" class="aud-loading">
        <i class="i-lucide-loader-2 animate-spin w-5 h-5" />
        <span>Carregando logs de auditoria...</span>
      </div>

      <!-- Tabela real -->
      <div v-else class="overflow-x-auto">
        <table class="aud-table">
          <thead>
            <tr class="aud-thead-row">
              <th class="aud-th">Data / Hora</th>
              <th class="aud-th">Ação</th>
              <th class="aud-th">Usuário / Perfil</th>
              <th class="aud-th">Módulo &amp; Detalhes</th>
              <th class="aud-th">IP</th>
              <th class="aud-th aud-th--center">Info</th>
            </tr>
          </thead>
          <tbody>
            <!-- Estado vazio -->
            <tr v-if="auditLogs.length === 0">
              <td colspan="6" class="aud-empty-cell">
                <div class="aud-empty-state">
                  <i class="i-lucide-shield-off w-6 h-6" />
                  <p>Nenhum log de auditoria encontrado para este paciente.</p>
                  <p class="aud-empty-hint">
                    Tente ajustar os filtros ou verifique suas permissões.
                  </p>
                </div>
              </td>
            </tr>

            <!-- Linhas de log -->
            <template v-for="log in auditLogs" :key="log.id">
              <tr class="aud-row">
                <!-- Data/Hora -->
                <td class="aud-td aud-td--mono aud-td--dim">
                  {{ formatAuditDateTime(log.occurred_at) }}
                </td>

                <!-- Tipo de ação -->
                <td class="aud-td">
                  <span
                    class="aud-action-badge"
                    :class="formatAuditAction(log.action).color"
                  >
                    <i
                      class="w-3 h-3"
                      :class="formatAuditAction(log.action).icon"
                    />
                    {{ formatAuditAction(log.action).label }}
                  </span>
                </td>

                <!-- Usuário / Perfil -->
                <td class="aud-td">
                  <div class="aud-user-cell">
                    <div class="aud-avatar">
                      {{ getInitials(log.actor_name) }}
                    </div>
                    <div>
                      <p class="aud-user-name">
                        {{ log.actor_name || 'Sistema' }}
                      </p>
                      <p class="aud-user-role">
                        {{ log.actor_role || '—' }}
                      </p>
                    </div>
                  </div>
                </td>

                <!-- Módulo & Detalhes -->
                <td class="aud-td aud-td--details">
                  <span class="aud-module-name">{{
                    log.resource_type || 'Ficha'
                  }}</span>
                  <span
v-if="log.resource_id" class="aud-module-id"
                    >#{{ log.resource_id }}</span
                  >

                  <!-- Diff de campos alterados -->
                  <div
                    v-if="
                      log.changed_fields &&
                      Object.keys(log.changed_fields).length > 0
                    "
                    class="aud-diff"
                  >
                    <div
                      v-for="(vals, field) in log.changed_fields"
                      :key="field"
                      class="aud-diff-row"
                    >
                      <span class="aud-diff-field">{{ field }}:</span>
                      <span class="aud-diff-old">{{
                        vals[0] !== null ? vals[0] : 'vazio'
                      }}</span>
                      <i
                        class="i-lucide-arrow-right w-2.5 h-2.5 text-slate-600"
                      />
                      <span class="aud-diff-new">{{
                        vals[1] !== null ? vals[1] : 'vazio'
                      }}</span>
                    </div>
                  </div>

                  <!-- Snapshot new_value -->
                  <div
                    v-else-if="log.new_value"
                    class="aud-snapshot"
                    :title="JSON.stringify(log.new_value)"
                  >
                    {{ JSON.stringify(log.new_value).slice(0, 80)
                    }}{{ JSON.stringify(log.new_value).length > 80 ? '…' : '' }}
                  </div>
                </td>

                <!-- IP -->
                <td class="aud-td aud-td--mono aud-td--dim">
                  {{ log.ip_address || '—' }}
                </td>

                <!-- Ver detalhes -->
                <td class="aud-td aud-td--center">
                  <button
                    class="aud-detail-btn"
                    :title="
                      expandedLogs.has(log.id)
                        ? 'Recolher detalhes'
                        : 'Ver detalhes completos'
                    "
                    @click="toggleLogDetails(log.id)"
                  >
                    <i
                      class="w-4 h-4"
                      :class="
                        expandedLogs.has(log.id)
                          ? 'i-lucide-eye-off'
                          : 'i-lucide-eye'
                      "
                    />
                  </button>
                </td>
              </tr>

              <!-- Linha expandida -->
              <tr v-if="expandedLogs.has(log.id)" class="aud-expanded-row">
                <td colspan="6" class="aud-expanded-cell">
                  <div class="aud-expanded-body">
                    <i class="i-lucide-info w-4 h-4 aud-expanded-icon" />
                    <div>
                      <p class="aud-expanded-title">
                        Registro de Ação Detalhado
                      </p>
                      <p class="aud-expanded-text">
                        {{ generateDetailedAuditText(log) }}
                      </p>

                      <!-- Diff completo -->
                      <div
                        v-if="
                          log.action === 'update' &&
                          log.changed_fields &&
                          Object.keys(log.changed_fields).length > 0
                        "
                        class="aud-expanded-diff"
                      >
                        <p class="aud-expanded-diff-title">
                          Histórico de Alterações (De → Para)
                        </p>
                        <ul class="aud-expanded-diff-list">
                          <li
                            v-for="(vals, field) in log.changed_fields"
                            :key="field"
                            class="aud-expanded-diff-item"
                          >
                            <span class="aud-diff-f">{{ field }}</span>
                            <span class="aud-diff-o">{{
                              vals[0] !== null ? vals[0] : 'nulo'
                            }}</span>
                            <i
                              class="i-lucide-arrow-right w-3 h-3 text-slate-600"
                            />
                            <span class="aud-diff-n">{{
                              vals[1] !== null ? vals[1] : 'nulo'
                            }}</span>
                          </li>
                        </ul>
                      </div>
                    </div>
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Rodapé: nota de imutabilidade + paginação -->
    <div class="aud-footer mt-5">
      <p class="aud-footer-note">
        <i class="i-lucide-lock w-3 h-3" />
        Registros imutáveis — gravados permanentemente no banco.
        <span class="aud-footer-total"
          >Total: {{ auditMeta.total_count }} eventos</span
        >
      </p>
      <div class="aud-pagination">
        <span class="aud-page-info"
          >Página {{ auditMeta.current_page }} de
          {{ auditMeta.total_pages }}</span
        >
        <div class="flex gap-2">
          <button
            class="btn-secondary disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="auditFilters.page <= 1 || isAuditLoading"
            @click="auditPagePrev"
          >
            ← Anterior
          </button>
          <button
            class="btn-secondary disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="
              auditFilters.page >= auditMeta.total_pages || isAuditLoading
            "
            @click="auditPageNext"
          >
            Próxima →
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
