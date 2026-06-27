<template>

    <div class="notif-root" @click="openDropdownIndex = null; dropdownPos = null;">
      <!-- Dropdown flutuante (INBOXES SELECT) — classes com tokens de tema
           (claro/escuro). Teleportado pro body, mas mantém o data-v do escopo,
           então o CSS scoped abaixo alcança. Posição vem inline (dinâmica). -->
      <teleport to="body">
        <div
          v-if="(showNewInboxDropdown || showEditInboxDropdown) && dropdownPos"
          class="inbox-dropdown"
          :style="{
            top: dropdownPos.top + 'px',
            left: dropdownPos.left + 'px',
            width: dropdownPos.width + 'px',
          }"
          @click.stop
        >
          <div
            v-if="!availableInboxes || availableInboxes.length === 0"
            class="inbox-dropdown-empty"
          >
            Nenhuma inbox disponível
          </div>

          <div
            v-for="inbox in availableInboxes"
            :key="'dd-' + inbox.id"
            class="inbox-dropdown-item"
            :class="{
              selected: showNewInboxDropdown
                ? isNewInboxSelected(inbox)
                : isEditInboxSelected(inbox),
            }"
            @click.stop="
              showNewInboxDropdown
                ? toggleNewInbox(inbox)
                : toggleEditInbox(inbox)
            "
          >
            <i
              class="inbox-dropdown-check"
              :class="
                (
                  showNewInboxDropdown
                    ? isNewInboxSelected(inbox)
                    : isEditInboxSelected(inbox)
                )
                  ? 'i-lucide-check-square'
                  : 'i-lucide-square'
              "
            />
            <span class="inbox-dropdown-name">{{ inbox.name || 'Inbox' }}</span>
            <span class="inbox-dropdown-type">{{
              String(inbox.channel_type || '').replace('Channel::', '')
            }}</span>
          </div>
        </div>
      </teleport>

      <!-- Header -->
      <div class="flex items-center justify-between mb-6">
        <div>
          <h2 class="section-title mb-0">Notificações e lembretes</h2>
          <p class="section-sub-title">
            Configure mensagens automáticas enviadas aos pacientes via WhatsApp,
            Instagram e Telegram.
          </p>
        </div>
        <button class="add-exception-btn" @click="openNewModal">
          <i class="i-lucide-plus size-4" />
          <span>Nova regra</span>
        </button>
      </div>

      <!-- Loading state -->
      <div v-if="notifRulesLoading" class="notif-grid">
        <div v-for="n in 4" :key="n" class="notif-card notif-card-skeleton">
          <div class="skeleton-head">
            <div class="skeleton-icon" />
            <div class="skeleton-lines">
              <div class="skeleton-line skeleton-line-lg" />
              <div class="skeleton-line skeleton-line-sm" />
            </div>
          </div>
          <div
            class="skeleton-line skeleton-line-full"
            style="height: 60px; border-radius: 8px; margin-top: 8px"
          />
        </div>
      </div>

      <!-- Empty state -->
      <div v-else-if="notifRules.length === 0" class="notif-empty">
        <i class="i-lucide-bell-off notif-empty-ico" />
        <p class="notif-empty-title">Nenhuma regra criada ainda</p>
        <p class="notif-empty-sub">
          Clique em "+ Nova regra" para criar a primeira notificação automática.
        </p>
      </div>

      <!-- Grid de cards -->
      <div v-else class="notif-cards-list">
        <div v-for="rule in notifRules" :key="rule.id" class="notif-rule-item">
          <div class="notif-rule-main">
            <!-- Ícone e Info principal -->
            <div class="notif-rule-info">
              <div
                class="rule-icon-sq"
                :class="`bg-${rule.iconColor}-500/10 text-${rule.iconColor}-400`"
              >
                <i :class="[rule.icon]" class="size-4" />
              </div>
              <div class="notif-rule-details">
                <div class="notif-rule-header-row">
                  <span class="notif-rule-name">{{ rule.title }}</span>
                  <div class="notif-rule-badges">
                    <span
                      v-if="
                        rule.trigger_offset_hours !== null &&
                        rule.trigger_offset_hours !== undefined &&
                        rule.trigger_offset_hours !== ''
                      "
                      class="notif-badge-time"
                    >
                      <i class="i-lucide-clock-4 size-3" />
                      {{ formatOffset(rule) }}
                    </span>
                    <span
                      v-else-if="
                        rule.rule_type && rule.rule_type !== 'reminder'
                      "
                      class="notif-badge-type"
                    >
                      {{ ruleTypeLabel(rule.rule_type) }}
                    </span>
                  </div>
                </div>
                <div class="notif-rule-channels">
                  <span
                    v-for="(inbox, ii) in rule.inboxes || []"
                    :key="ii"
                    class="notif-channel-tag"
                    :class="`channel-${inbox.color}`"
                  >
                    {{ inbox.label }}
                  </span>
                </div>
              </div>
            </div>

            <!-- Ações compactas -->
            <div class="notif-rule-actions">
              <button
                class="notif-action-icon"
                title="Editar"
                @click="openEditModal(rule)"
              >
                <i class="i-lucide-pencil size-4.5" />
              </button>
              <button
                class="notif-action-icon"
                title="IA"
                @click="openAiModal(rule)"
              >
                <i class="i-lucide-sparkles size-4.5" />
              </button>
              <button
                class="notif-action-icon"
                :class="{ active: previewRuleIds.includes(rule.id) }"
                title="Preview"
                @click="togglePreview(rule.id)"
              >
                <i
                  :class="
                    previewRuleIds.includes(rule.id)
                      ? 'i-lucide-eye-off'
                      : 'i-lucide-eye'
                  "
                  class="size-4.5"
                />
              </button>
              <div class="notif-divider" />
              <button
                class="notif-action-icon text-red-400 hover:bg-red-500/10"
                title="Excluir"
                @click="deleteNotifRule(rule.id)"
              >
                <i class="i-lucide-trash-2 size-4.5" />
              </button>
            </div>
          </div>

          <!-- Pré-visualização da Mensagem -->
          <div class="notif-message-preview">
            <p
              v-if="previewRuleIds.includes(rule.id)"
              class="notif-preview-text"
              v-html="getPreviewText(rule.message)"
            />
            <p
              v-else
              class="notif-preview-text"
              v-html="highlightVars(rule.message)"
            />
          </div>
        </div>
      </div>

      <!-- Modal: Editar regra -->
      <teleport to="body">
        <div
          v-if="notifEditModal"
          class="modal-overlay"
          @click.self="closeEditModal"
        >
          <div
            class="modal-box"
            @click.stop="openDropdownIndex = null; dropdownPos = null;"
          >
            <div class="modal-header">
              <span class="modal-title">Editar mensagem automática</span>
              <button class="modal-close" @click="closeEditModal">
                <i class="i-lucide-x size-[16px]" />
              </button>
            </div>
            <div class="modal-body">
              <label class="modal-label">Título da regra</label>
              <input
                v-model="notifEditTarget.title"
                class="modal-input"
                placeholder="Ex: Confirmação de agendamento"
              />

              <!-- Tipo de regra -->
              <label class="modal-label">Tipo de disparo</label>
              <FormSelect
                v-model="notifEditTarget.rule_type"
                :options="notifRuleTypes"
              />

              <!-- Offset de tempo (só para lembretes e followup) -->
              <div
                v-if="
                  ['reminder', 'followup'].includes(notifEditTarget.rule_type)
                "
                class="offset-field"
              >
                <label class="modal-label">
                  {{
                    notifEditTarget.rule_type === 'reminder'
                      ? 'Enviar quanto tempo antes da consulta? *'
                      : 'Enviar quanto tempo após o término da consulta? *'
                  }}
                </label>
                <div class="modern-offset-container">
                  <div class="modern-offset-input-wrap">
                    <i class="i-lucide-clock-4 modern-offset-icon" />
                    <input
                      v-model.number="notifEditTarget.trigger_offset_hours"
                      type="number"
                      min="1"
                      :step="
                        notifEditTarget._offsetUnit === 'minutes'
                          ? 1
                          : notifEditTarget._offsetUnit === 'days'
                            ? 1
                            : 0.5
                      "
                      class="modern-offset-input"
                      :placeholder="
                        notifEditTarget._offsetUnit === 'minutes'
                          ? 'Ex: 30'
                          : 'Ex: 24'
                      "
                    />
                  </div>
                  <!-- Segmented Control (Unidades) -->
                  <div class="segmented-control">
                    <button
                      type="button"
                      class="segment-btn"
                      :class="{
                        active: notifEditTarget._offsetUnit === 'minutes',
                      }"
                      @click="notifEditTarget._offsetUnit = 'minutes'"
                    >
                      Min
                    </button>
                    <button
                      type="button"
                      class="segment-btn"
                      :class="{
                        active: notifEditTarget._offsetUnit === 'hours',
                      }"
                      @click="notifEditTarget._offsetUnit = 'hours'"
                    >
                      Hrs
                    </button>
                    <button
                      type="button"
                      class="segment-btn"
                      :class="{
                        active: notifEditTarget._offsetUnit === 'days',
                      }"
                      @click="notifEditTarget._offsetUnit = 'days'"
                    >
                      Dias
                    </button>
                  </div>
                </div>
                <p class="offset-hint">
                  <span v-if="notifEditTarget._offsetUnit === 'days'">
                    Ex: 1 = 1 dia, 2 = 2 dias, 3 = 3 dias
                  </span>
                  <span v-else-if="notifEditTarget._offsetUnit === 'hours'">
                    Ex: 2 = 2h, 24 = 1 dia, 48 = 2 dias, 72 = 3 dias
                  </span>
                  <span v-else> Ex: 30 = meia hora, 60 = 1h, 120 = 2h </span>
                </p>
              </div>

              <!-- Inbox multi-select (Editar Regra) -->
              <label class="modal-label">
                <i class="i-lucide-inbox" />
                Inboxes (caixas de entrada)
              </label>
              <div
                v-if="
                  notifEditTarget &&
                  notifEditTarget.inboxes &&
                  notifEditTarget.inboxes.length
                "
                class="new-inboxes-list"
              >
                <span
                  v-for="(inb, ii) in notifEditTarget.inboxes"
                  :key="'edit-inb-' + ii"
                  class="nc-inbox-tag nc-inbox-wa inbox-chip-removable"
                >
                  {{ inb.label }}
                  <button
                    class="inbox-chip-remove"
                    type="button"
                    @click="notifEditTarget.inboxes.splice(ii, 1)"
                  >
                    <i class="i-lucide-x" />
                  </button>
                </span>
              </div>

              <!-- Dropdown Trigger Selector (Editar) -->
              <div
                class="inbox-add-trigger"
                :class="{ open: showEditInboxDropdown }"
                @click.stop="toggleDropdown('edit_inbox', $event)"
              >
                <i class="i-lucide-inbox inbox-add-icon" />
                <span class="inbox-add-label">Adicionar Inbox</span>
                <i class="i-lucide-chevron-down inbox-add-icon" />
              </div>

              <label class="modal-label">Mensagem</label>
              <div class="msg-editor">
                <div
                  ref="editHighlight"
                  class="msg-editor-backdrop"
                  aria-hidden="true"
                  v-html="renderMessageHighlight(notifEditTarget.message)"
                />
                <textarea
                  ref="editTextarea"
                  v-model="notifEditTarget.message"
                  class="msg-editor-input"
                  placeholder="Digite a mensagem..."
                  @scroll="syncScroll('edit')"
                />
              </div>

              <label class="modal-label">Inserir variável</label>
              <div class="modal-vars">
                <button
                  v-for="v in notifVars"
                  :key="v.key"
                  class="var-chip"
                  :title="v.desc"
                  @click="insertVarEditHandler(v.key)"
                >
                  {{ v.key }}
                </button>
              </div>
            </div>
            <div class="modal-footer">
              <button class="modal-btn-cancel" @click="closeEditModal">
                Cancelar
              </button>
              <button class="modal-btn-save" @click="saveEditModal">
                Salvar
              </button>
            </div>
          </div>
        </div>
      </teleport>
      <!-- Modal: IA -->
      <teleport to="body">
        <div
          v-if="notifAiModal"
          class="modal-overlay"
          @click.self="closeAiModal"
        >
          <div class="modal-box modal-box-ai" @click.stop>
            <div class="modal-header">
              <span class="modal-title"><i
                  class="i-lucide-sparkles size-[15px]"
                  style="color: #a78bfa; margin-right: 6px"
                />Melhorar com IA</span>
              <button class="modal-close" @click="closeAiModal">
                <i class="i-lucide-x size-[16px]" />
              </button>
            </div>
            <div class="modal-body">
              <p class="modal-label" style="margin-bottom: 10px">
                Escolha como deseja melhorar a mensagem:
              </p>
              <div class="ai-actions">
                <button
                  class="ai-action-btn"
                  :class="{ active: notifAiAction === 'grammar' }"
                  @click="runAiAction('grammar')"
                >
                  <i class="i-lucide-spell-check size-[14px]" /> Corrigir
                  ortografia
                </button>
                <button
                  class="ai-action-btn"
                  :class="{ active: notifAiAction === 'improve' }"
                  @click="runAiAction('improve')"
                >
                  <i class="i-lucide-wand-2 size-[14px]" /> Melhorar texto
                </button>
                <button
                  class="ai-action-btn"
                  :class="{ active: notifAiAction === 'professional' }"
                  @click="runAiAction('professional')"
                >
                  <i class="i-lucide-briefcase size-[14px]" /> Mais profissional
                </button>
                <button
                  class="ai-action-btn"
                  :class="{ active: notifAiAction === 'friendly' }"
                  @click="runAiAction('friendly')"
                >
                  <i class="i-lucide-smile size-[14px]" /> Mais amigável
                </button>
              </div>

              <div v-if="notifAiLoading" class="ai-loading">
                <i
                  class="i-lucide-loader-circle animate-spin size-[20px]"
                  style="color: #a78bfa"
                />
                <span>Gerando sugestão...</span>
              </div>

              <div
                v-if="notifAiResult && !notifAiLoading"
                class="ai-result-wrap"
              >
                <label class="modal-label">Sugestão da IA:</label>
                <div class="ai-result-text">{{ notifAiResult }}</div>
              </div>
            </div>
            <div class="modal-footer">
              <button class="modal-btn-cancel" @click="closeAiModal">
                Cancelar
              </button>
              <button
                class="modal-btn-save"
                :disabled="!notifAiResult || notifAiLoading"
                @click="applyAiResult"
              >
                <i class="i-lucide-check size-[14px]" /> Aplicar sugestão
              </button>
            </div>
          </div>
        </div>
      </teleport>

      <!-- ─── Painel de Histórico de Disparos ─── -->
      <div class="logs-panel-modern">
        <button class="logs-toggle-clean" @click="toggleLogsPanel">
          <div class="flex items-center gap-2">
            <i class="i-lucide-history size-3.5 opacity-60" />
            <span>Histórico de disparos</span>
          </div>
          <i
            class="i-lucide-chevron-right size-3.5 transition-transform duration-200"
            :class="{ 'rotate-90': logsOpen }"
          />
        </button>

        <div v-if="logsOpen" class="logs-body">
          <!-- Header com filtros -->
          <div class="logs-filters">
            <FormSelect
              v-model="logsFilter"
              :options="logsStatusOptions"
              class="logs-filter-select"
              @change="fetchLogs(1)"
            >
              <template #selected="{ option }">
                <i
                  :class="(option || logsStatusOptions[0]).icon"
                  class="size-3.5 shrink-0"
                  :style="{ color: (option || logsStatusOptions[0]).iconColor }"
                />
                <span>{{ (option || logsStatusOptions[0]).label }}</span>
              </template>
              <template #option="{ option }">
                <i
                  :class="option.icon"
                  class="size-3.5 shrink-0"
                  :style="{ color: option.iconColor }"
                />
                <span>{{ option.label }}</span>
              </template>
            </FormSelect>
            <button
              class="logs-refresh-btn"
              :disabled="logsLoading"
              @click="fetchLogs"
            >
              <i
                class="i-lucide-refresh-cw size-4.5"
                :class="logsLoading ? 'animate-spin' : ''"
              />
            </button>
          </div>

          <!-- Loading -->
          <div v-if="logsLoading" class="logs-loading">
            <i class="i-lucide-loader-circle animate-spin" /> Carregando...
          </div>

          <!-- Tabela de logs -->
          <div v-else-if="logsData.length === 0" class="logs-empty">
            Nenhum disparo registrado ainda.
          </div>
          <table v-else class="logs-table">
            <thead>
              <tr>
                <th>Regra</th>
                <th>Evento</th>
                <th>Data do agendamento</th>
                <th>Enviado em</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="log in logsData"
                :key="log.id"
                :class="`log-row log-row-${log.status}`"
              >
                <td>
                  <div class="log-rule-name">
                    <i
                      class="log-rule-ico"
                      :class="[
                        log.rule && log.rule.icon
                          ? log.rule.icon
                          : 'i-lucide-bell',
                      ]"
                      :style="{
                        color: ruleIconColorHex(
                          log.rule && log.rule.icon_color
                        ),
                      }"
                    />
                    {{ log.rule && log.rule.title ? log.rule.title : '—' }}
                  </div>
                </td>
                <td class="log-event-title">
                  {{ log.event && log.event.title ? log.event.title : '—' }}
                </td>
                <td class="log-date">
                  {{ formatDateTime(log.event && log.event.starts_at) }}
                </td>
                <td class="log-date">{{ formatDateTime(log.sent_at) }}</td>
                <td>
                  <span class="log-badge" :class="[`log-badge-${log.status}`]">
                    {{ log.status }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>

          <!-- Paginação -->
          <div
            v-if="logsMeta.total > logsMeta.per_page"
            class="logs-pagination"
          >
            <button
              class="logs-page-btn"
              :disabled="logsMeta.page <= 1"
              @click="fetchLogs(logsMeta.page - 1)"
            >
              <i class="i-lucide-chevron-left size-[13px]" />
            </button>
            <span class="logs-page-info">{{ logsMeta.page }} /
              {{ Math.ceil(logsMeta.total / logsMeta.per_page) }}</span>
            <button
              class="logs-page-btn"
              :disabled="
                logsMeta.page >= Math.ceil(logsMeta.total / logsMeta.per_page)
              "
              @click="fetchLogs(logsMeta.page + 1)"
            >
              <i class="i-lucide-chevron-right size-[13px]" />
            </button>
          </div>
        </div>
      </div>

      <!-- Modal: Nova Regra -->
      <teleport to="body">
        <div
          v-if="notifNewModal"
          class="modal-overlay"
          @click.self="closeNewModal"
        >
          <div
            class="modal-box modal-box-new"
            @click.stop="openDropdownIndex = null; dropdownPos = null;"
          >
            <div class="modal-header">
              <span class="modal-title">Nova regra de notificação</span>
              <button class="modal-close" @click="closeNewModal">
                <i class="i-lucide-x size-[16px]" />
              </button>
            </div>
            <div v-if="notifNewDraft" class="modal-body">
              <label class="modal-label">Título da regra *</label>
              <input
                v-model="notifNewDraft.title"
                class="modal-input"
                placeholder="Ex: Lembrete pós consulta"
              />

              <!-- Tipo de disparo -->
              <label class="modal-label">Tipo de disparo *</label>
              <FormSelect
                v-model="notifNewDraft.rule_type"
                :options="notifRuleTypes"
                @change="
                  if (
                    notifNewDraft.rule_type !== 'reminder' &&
                    notifNewDraft.rule_type !== 'followup'
                  ) {
                    notifNewDraft.trigger_offset_hours = null;
                  }
                "
              />

              <!-- Offset de tempo (só para Lembretes e Follow-up) -->
              <div
                v-if="
                  ['reminder', 'followup'].includes(notifNewDraft.rule_type)
                "
                class="offset-field"
              >
                <label class="modal-label">
                  {{
                    notifNewDraft.rule_type === 'reminder'
                      ? 'Enviar quanto tempo antes da consulta? *'
                      : 'Enviar quanto tempo após o término da consulta? *'
                  }}
                </label>
                <div class="modern-offset-container">
                  <div class="modern-offset-input-wrap">
                    <i class="i-lucide-clock-4 modern-offset-icon" />
                    <input
                      v-model.number="notifNewDraft.trigger_offset_hours"
                      type="number"
                      min="1"
                      :step="
                        notifNewDraft._offsetUnit === 'minutes'
                          ? 1
                          : notifNewDraft._offsetUnit === 'days'
                            ? 1
                            : 0.5
                      "
                      class="modern-offset-input"
                      :placeholder="
                        notifNewDraft._offsetUnit === 'minutes'
                          ? 'Ex: 30'
                          : 'Ex: 24'
                      "
                    />
                  </div>
                  <!-- Segmented Control (Unidades) -->
                  <div class="segmented-control">
                    <button
                      type="button"
                      class="segment-btn"
                      :class="{
                        active: notifNewDraft._offsetUnit === 'minutes',
                      }"
                      @click="notifNewDraft._offsetUnit = 'minutes'"
                    >
                      Min
                    </button>
                    <button
                      type="button"
                      class="segment-btn"
                      :class="{ active: notifNewDraft._offsetUnit === 'hours' }"
                      @click="notifNewDraft._offsetUnit = 'hours'"
                    >
                      Hrs
                    </button>
                    <button
                      type="button"
                      class="segment-btn"
                      :class="{ active: notifNewDraft._offsetUnit === 'days' }"
                      @click="notifNewDraft._offsetUnit = 'days'"
                    >
                      Dias
                    </button>
                  </div>
                </div>
                <p class="offset-hint">
                  <span v-if="notifNewDraft._offsetUnit === 'days'">
                    Ex: 1 = 1 dia, 2 = 2 dias, 3 = 3 dias
                  </span>
                  <span v-else-if="notifNewDraft._offsetUnit === 'hours'">
                    Ex: 2 = 2h, 24 = 1 dia, 48 = 2 dias, 72 = 3 dias
                  </span>
                  <span v-else> Ex: 30 = meia hora, 60 = 1h, 120 = 2h </span>
                </p>
              </div>

              <div class="svc-row-fields">
                <div>
                  <label class="modal-label">Ícone</label>
                  <FormSelect
                    v-model="notifNewDraft.icon"
                    :options="notifIconOptions"
                  >
                    <template #selected="{ option }">
                      <i v-if="option" :class="option.icon" class="size-4" />
                      <span>{{ option ? option.label : 'Selecione' }}</span>
                    </template>
                    <template #option="{ option }">
                      <i :class="option.icon" class="size-4" />
                      <span>{{ option.label }}</span>
                    </template>
                  </FormSelect>
                </div>
                <div>
                  <label class="modal-label">Cor do ícone</label>
                  <FormSelect
                    v-model="notifNewDraft.iconColor"
                    :options="notifIconColors"
                  />
                </div>
              </div>

              <!-- Inbox multi-select (Nova Regra) -->
              <label class="modal-label">
                <i class="i-lucide-inbox" />
                Inboxes (caixas de entrada)
              </label>
              <!-- Tags das selecionadas -->
              <div
                v-if="
                  notifNewDraft &&
                  notifNewDraft.inboxes &&
                  notifNewDraft.inboxes.length
                "
                class="new-inboxes-list"
              >
                <span
                  v-for="(inb, ii) in notifNewDraft.inboxes"
                  :key="'new-inb-' + ii"
                  class="nc-inbox-tag nc-inbox-wa inbox-chip-removable"
                >
                  {{ inb.label }}
                  <button
                    class="inbox-chip-remove"
                    type="button"
                    @click="notifNewDraft.inboxes.splice(ii, 1)"
                  >
                    <i class="i-lucide-x" />
                  </button>
                </span>
              </div>

              <!-- Dropdown Trigger Selector (Nova Regra) -->
              <div
                class="inbox-add-trigger"
                :class="{ open: showNewInboxDropdown }"
                @click.stop="toggleDropdown('new_inbox', $event)"
              >
                <i class="i-lucide-inbox inbox-add-icon" />
                <span class="inbox-add-label">Adicionar Inbox</span>
                <i class="i-lucide-chevron-down inbox-add-icon" />
              </div>

              <label class="modal-label">Mensagem *</label>
              <div class="msg-editor">
                <div
                  ref="newHighlight"
                  class="msg-editor-backdrop"
                  aria-hidden="true"
                  v-html="renderMessageHighlight(notifNewDraft.message)"
                />
                <textarea
                  ref="newTextarea"
                  v-model="notifNewDraft.message"
                  class="msg-editor-input"
                  placeholder="Digite a mensagem automática..."
                  @scroll="syncScroll('new')"
                />
              </div>

              <label class="modal-label">Inserir variável</label>
              <div class="modal-vars">
                <button
                  v-for="v in notifVars"
                  :key="v.key"
                  class="var-chip"
                  :title="v.desc"
                  @click="insertVarNewHandler(v.key)"
                >
                  {{ v.key }}
                </button>
              </div>
            </div>
            <div class="modal-footer">
              <button class="modal-btn-cancel" @click="closeNewModal">
                Cancelar
              </button>
              <button class="modal-btn-save" @click="saveNewRule">
                <i class="i-lucide-plus size-[14px]" /> Criar regra
              </button>
            </div>
          </div>
        </div>
      </teleport>
    </div>

    </template>

<script setup>
import { ref } from 'vue';
import { useStore } from 'vuex';
import { useSettingsNotifications } from '../composables/useSettingsNotifications';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';


const store = useStore();

const {
  notifRuleTypes, notifVars, notifIconOptions, notifIconColors,
  notifEditModal, notifEditTarget, previewRuleIds,
  notifAiModal, notifAiTarget, notifAiAction, notifAiLoading, notifAiResult,
  notifNewModal, notifNewDraft,
  logsOpen, logsLoading, logsData, logsMeta, logsFilter,
  openDropdownIndex, dropdownPos, showNewInboxDropdown, showEditInboxDropdown,
  notifRules, notifRulesLoading, availableInboxes,
  highlightVars, ruleIconColorHex, ruleTypeLabel, formatOffset, formatDateTime,
  togglePreview, getPreviewText, toggleDropdown,
  openEditModal, closeEditModal, saveEditModal,
  openAiModal, closeAiModal, runAiAction, applyAiResult,
  openNewModal, closeNewModal, saveNewRule, deleteNotifRule,
  toggleNewInbox, isNewInboxSelected, toggleEditInbox, isEditInboxSelected,
  toggleLogsPanel, fetchLogs, insertVarInEdit, insertVarInNew
} = useSettingsNotifications(store);

const editTextarea = ref(null);
const newTextarea = ref(null);
// Backdrops do editor de mensagem (camada que colore as variáveis).
const editHighlight = ref(null);
const newHighlight = ref(null);

// Mantém o backdrop alinhado ao scroll do textarea (texto transparente em
// cima, destaque colorido atrás — precisam rolar juntos).
const syncScroll = which => {
  const ta = which === 'new' ? newTextarea.value : editTextarea.value;
  const bd = which === 'new' ? newHighlight.value : editHighlight.value;
  if (ta && bd) {
    bd.scrollTop = ta.scrollTop;
    bd.scrollLeft = ta.scrollLeft;
  }
};

// Renderiza a mensagem escapada com os {placeholders} envoltos em <span msg-var>
// pra colorir igual aos chips de variáveis abaixo. O '\n' final faz o backdrop
// acompanhar a última linha do textarea (truque clássico de highlight overlay).
const renderMessageHighlight = text => {
  if (!text) return '';
  const escaped = String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
  return (
    escaped.replace(
      /\{[a-zA-Z_]+\}/g,
      m => `<span class="msg-var">${m}</span>`
    ) + '\n'
  );
};

// Opções do filtro de status do histórico — ícones premium (sem emoji).
const logsStatusOptions = [
  { value: '', label: 'Todos os status', icon: 'i-lucide-list-filter', iconColor: 'rgb(var(--slate-10))' },
  { value: 'sent', label: 'Enviados', icon: 'i-lucide-circle-check', iconColor: '#16a34a' },
  { value: 'failed', label: 'Falhas', icon: 'i-lucide-circle-x', iconColor: '#dc2626' },
  { value: 'skipped', label: 'Pulados', icon: 'i-lucide-circle-minus', iconColor: 'rgb(var(--slate-9))' },
];

const insertVarEditHandler = (k) => insertVarInEdit(k, editTextarea.value);
const insertVarNewHandler = (k) => insertVarInNew(k, newTextarea.value);
</script>

<style scoped>
/* ═══════════ NOTIFICAÇÕES AUTOMÁTICAS ═══════════ */
/* Notificações e Lembretes */
.notif-root {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

.section-sub-title {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0;
}

.notif-cards-list {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
  overflow-y: auto;
  padding-bottom: 24px;
}

.notif-rule-item {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 12px;
  padding: 16px;
  transition: all 0.2s;
}

.notif-rule-item:hover {
  border-color: rgb(var(--slate-7));
  background: rgb(var(--slate-3));
}

.notif-rule-main {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}

.notif-rule-info {
  display: flex;
  align-items: center;
  gap: 12px;
  flex: 1;
  min-width: 0;
}

.notif-rule-details {
  display: flex;
  flex-direction: column;
  gap: 4px;
  flex: 1;
  min-width: 0;
}

.notif-rule-header-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.notif-rule-name {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 150px;
}

.notif-rule-badges {
  display: flex;
  align-items: center;
  gap: 6px;
}

.notif-badge-time {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  @apply text-sm;
  font-weight: 700;
  padding: 1px 8px;
  border-radius: 999px;
  background: rgba(59, 130, 246, 0.12);
  color: rgb(var(--blue-9));
  border: 1px solid rgba(59, 130, 246, 0.25);
}

.notif-badge-type {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  @apply text-sm;
  font-weight: 700;
  padding: 1px 8px;
  border-radius: 999px;
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-9));
  border: 1px solid rgb(var(--slate-5));
}

.notif-rule-channels {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.notif-channel-tag {
  @apply text-sm;
  font-weight: 600;
  padding: 0px 6px;
  border-radius: 4px;
  opacity: 0.8;
}

.channel-wa {
  background: rgba(34, 197, 94, 0.1);
  color: #16a34a;
  border: 1px solid rgba(34, 197, 94, 0.3);
}
.channel-ig {
  background: rgba(236, 72, 153, 0.1);
  color: #db2777;
  border: 1px solid rgba(236, 72, 153, 0.3);
}
.channel-tg {
  background: rgba(59, 130, 246, 0.1);
  color: rgb(var(--blue-9));
  border: 1px solid rgba(59, 130, 246, 0.3);
}

.notif-rule-actions {
  display: flex;
  align-items: center;
  background: rgba(100, 116, 139, 0.08);
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 2px;
  gap: 2px;
}

.notif-action-icon {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  color: rgb(var(--slate-9));
  transition: all 0.2s;
  cursor: pointer;
}

.notif-action-icon:hover {
  background: rgb(var(--slate-5));
  color: rgb(var(--slate-12));
}

.notif-action-icon.active {
  background: rgb(var(--blue-9));
  color: #fff;
}

.notif-divider {
  width: 1px;
  height: 16px;
  background: rgb(var(--slate-6));
  margin: 0 4px;
}

.notif-message-preview {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  padding: 10px 14px;
}

.notif-preview-text {
  @apply text-sm;
  line-height: 1.55;
  color: rgb(var(--slate-11));
  margin: 0;
  word-break: break-word;
}

/* Painel de Histórico */
.logs-panel-modern {
  margin-top: 12px;
  border: 1px solid rgb(var(--slate-5));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-2));
  /* Não deixa o flex-column do .notif-root comprimir o painel (o empty-state
     usa flex:1 e antes "comia" a altura, cortando o conteúdo do histórico). */
  flex-shrink: 0;
}

.logs-toggle-clean {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  background: transparent;
  border: none;
  cursor: pointer;
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  transition: background 0.2s;
}

.logs-toggle-clean:hover {
  background: rgb(var(--slate-3));
}

.logs-body {
  padding: 0 16px 16px;
  border-top: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-1));
}

.logs-filters {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 0;
}

/* O filtro de status É um FormSelect (não um <select> nativo). A classe só
   controla a largura no flex — qualquer border/background/chevron aqui
   desenharia uma caixa POR CIMA da que o FormSelect já tem ("input duplicado").
   Ver [[feedback-form-select-padrao]]. */
.logs-filter-select {
  flex: 1;
  min-width: 0;
}

.logs-refresh-btn {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  color: rgb(var(--slate-9));
  cursor: pointer;
  transition: all 0.2s;
}

.logs-refresh-btn:hover:not(:disabled) {
  background: rgb(var(--slate-4));
  border-color: rgb(var(--slate-7));
  color: rgb(var(--slate-12));
}

.logs-table {
  width: 100%;
  border-collapse: collapse;
  @apply text-sm;
}

.logs-table th {
  text-align: left;
  padding: 8px;
  color: rgb(var(--slate-9));
  font-weight: 600;
  border-bottom: 1px solid rgb(var(--slate-4));
}

.logs-table td {
  padding: 8px;
  color: rgb(var(--slate-11));
  border-bottom: 1px solid rgba(var(--slate-4), 0.5);
}

.log-rule-name {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.log-badge {
  padding: 2px 6px;
  border-radius: 4px;
  @apply text-sm;
  font-weight: 700;
  text-transform: uppercase;
}

.log-badge-sent {
  background: rgba(34, 197, 94, 0.1);
  color: #16a34a;
}
.log-badge-failed {
  background: rgba(239, 68, 68, 0.1);
  color: #ef4444;
}
.log-badge-skipped {
  background: rgba(100, 116, 139, 0.1);
  color: rgb(var(--slate-9));
}


/* Preview bubble */
.preview-hint {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0 0 14px;
}
.preview-bubble {
  background: rgba(16, 185, 129, 0.08);
  border: 1px solid rgba(16, 185, 129, 0.25);
  border-radius: 14px 14px 14px 4px;
  padding: 14px 16px;
  @apply text-sm;
  line-height: 1.7;
  color: rgb(var(--slate-12));
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.06);
}

/* Offset Time Selector (Premium Design) */
.offset-field {
  margin-top: 14px;
}
.modern-offset-container {
  display: flex;
  align-items: center;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 12px;
  padding: 4px;
  gap: 4px;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}
.modern-offset-container:focus-within {
  border-color: rgb(var(--blue-9));
  background: rgb(var(--slate-2));
}

.modern-offset-input-wrap {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 12px;
  flex: 1;
}
.modern-offset-icon {
  color: rgb(var(--slate-8));
  @apply text-sm;
  flex-shrink: 0;
}
.modern-offset-input {
  background: transparent !important;
  border: none !important;
  font-size: 15px !important;
  font-weight: 700 !important;
  color: rgb(var(--slate-12)) !important;
  width: 100% !important;
  padding: 8px 0 !important;
  outline: none !important;
}

.segmented-control {
  display: flex;
  background: rgb(var(--slate-5));
  border-radius: 9px;
  padding: 2px;
  gap: 2px;
}
.segment-btn {
  border: none;
  background: transparent;
  padding: 6px 12px;
  border-radius: 7px;
  @apply text-sm;
  font-weight: 700;
  color: rgb(var(--slate-9));
  cursor: pointer;
  text-transform: uppercase;
  letter-spacing: 0.03em;
  transition: all 0.15s ease;
  white-space: nowrap;
}
.segment-btn:hover {
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-4));
}
.segment-btn.active {
  background: rgb(var(--blue-9));
  color: #fff;
  box-shadow: 0 2px 8px rgba(37, 99, 235, 0.3);
}

.offset-hint {
  @apply text-sm;
  color: rgb(var(--slate-8));
  margin-top: 6px;
  font-weight: 500;
  display: block;
  opacity: 0.8;
}

/* AI modal */
.ai-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  margin-bottom: 16px;
}
.ai-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-6));
  color: rgb(var(--slate-10));
  border-radius: 8px;
  padding: 9px 12px;
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s;
}
.ai-action-btn:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}
.ai-action-btn.active {
  background: rgba(124, 58, 237, 0.1);
  border-color: rgba(124, 58, 237, 0.4);
  color: #7c3aed;
}
.ai-loading {
  display: flex;
  align-items: center;
  gap: 10px;
  color: rgb(var(--slate-9));
  @apply text-sm;
  padding: 8px 0;
}
.ai-result-wrap {
  margin-top: 4px;
}
.ai-result-text {
  background: rgb(var(--slate-2));
  border: 1px solid rgba(124, 58, 237, 0.3);
  border-radius: 8px;
  padding: 12px;
  @apply text-sm;
  line-height: 1.6;
  color: rgb(var(--slate-12));
  margin-top: 6px;
  white-space: pre-wrap;
}

/* New rule modal inboxes */
.new-inboxes-list {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  min-height: 28px;
}

/* Chip da inbox selecionada — badge colorido sutil (mesmo padrão do
   .channel-wa dos cards). Antes dependia de .nc-inbox-tag/.nc-inbox-wa que
   nunca existiram aqui → ficava só texto + um × cinza invisível no claro. */
.nc-inbox-tag {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 6px 3px 10px;
  border-radius: 999px;
  font-size: 0.8125rem;
  font-weight: 500;
  line-height: 1.2;
}
.nc-inbox-wa {
  background: rgba(34, 197, 94, 0.1);
  color: #16a34a;
  border: 1px solid rgba(34, 197, 94, 0.3);
}
:root.dark .nc-inbox-wa {
  background: rgba(34, 197, 94, 0.16);
  color: #4ade80;
  border-color: rgba(34, 197, 94, 0.35);
}

/* Botão × dentro do chip — herda a cor do badge, hover sutil. Ícone no mesmo
   tamanho da fonte do texto (12px) pra ficar proporcional. */
.inbox-chip-removable {
  padding-right: 4px;
}
.inbox-chip-remove {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 16px;
  height: 16px;
  background: transparent;
  border: none;
  border-radius: 50%;
  cursor: pointer;
  color: inherit;
  opacity: 0.65;
  padding: 0;
  line-height: 1;
  flex-shrink: 0;
  transition: opacity 0.15s, background 0.15s;
}
.inbox-chip-remove:hover {
  opacity: 1;
  background: rgba(0, 0, 0, 0.08);
}
:root.dark .inbox-chip-remove:hover {
  background: rgba(255, 255, 255, 0.12);
}
.inbox-chip-remove i {
  width: 12px;
  height: 12px;
}

/* ─── Mobile: modais em tela cheia (largura + altura) ───
   Scoped vence o global .modal-box (0,2,0 > 0,1,0), então cobre também as
   variantes -new/-ai. 100dvh acompanha a barra do navegador no mobile. */
@media (max-width: 640px) {
  .modal-box {
    width: 100vw;
    max-width: 100vw;
    height: 100vh;
    height: 100dvh;
    max-height: 100vh;
    max-height: 100dvh;
    border-radius: 0;
  }
  .modal-overlay {
    backdrop-filter: none;
  }
}

/* ─── Seletor de Inbox (trigger + dropdown) — tokens de tema ───
   Antes era tudo inline com hex dark hardcoded (#1c2333, #e2e8f0…), o que
   renderizava preto no modo claro. Agora usa rgb(var(--slate-*)) e adapta. */
.inbox-add-trigger {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 8px;
  padding: 8px 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  font-size: 13px;
  color: rgb(var(--slate-11));
  cursor: pointer;
  min-height: 40px;
  transition: all 0.15s;
}
.inbox-add-trigger:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-1));
}
.inbox-add-trigger.open {
  border-color: rgb(var(--blue-8));
  background: rgb(var(--slate-1));
  box-shadow: 0 0 0 3px rgba(var(--blue-9), 0.12);
}
.inbox-add-icon {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
  color: rgb(var(--slate-8));
}
.inbox-add-label {
  flex: 1;
}

/* Teleportado pro body — mantém o data-v do escopo, então o scoped alcança.
   Só top/left/width vêm inline (posição dinâmica calculada no toggleDropdown). */
.inbox-dropdown {
  position: fixed;
  z-index: 100000;
  max-height: 220px;
  overflow-y: auto;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--border-strong));
  border-radius: 8px;
  padding: 6px;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.18);
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.inbox-dropdown-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-11));
  border-radius: 6px;
  cursor: pointer;
  user-select: none;
  transition: background 0.1s, color 0.1s;
}
.inbox-dropdown-item:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}
.inbox-dropdown-item.selected {
  color: rgb(var(--blue-9));
  background: rgba(var(--blue-9), 0.08);
}
.inbox-dropdown-check {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
  color: rgb(var(--slate-8));
}
.inbox-dropdown-item.selected .inbox-dropdown-check {
  color: rgb(var(--blue-9));
}
.inbox-dropdown-name {
  flex: 1;
}
.inbox-dropdown-type {
  font-size: 11px;
  color: rgb(var(--slate-8));
}
.inbox-dropdown-empty {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 10px 8px;
  font-size: 13px;
  color: rgb(var(--slate-9));
}

/* Inbox selector (lista clicável de opções) */
.inbox-selector {
  margin-top: 8px;
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  overflow: hidden;
  max-height: 180px;
  overflow-y: auto;
  background: rgb(var(--slate-2));
}
.inbox-option {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 9px 12px;
  cursor: pointer;
  transition: background 0.12s;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.inbox-option:last-child {
  border-bottom: none;
}
.inbox-option:hover {
  background: rgb(var(--slate-3));
}
.inbox-option-selected {
  background: rgba(59, 130, 246, 0.08);
}
.inbox-option-selected:hover {
  background: rgba(59, 130, 246, 0.13);
}
.inbox-option-check {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  color: rgb(var(--slate-8));
}
.inbox-option-selected .inbox-option-check {
  color: rgb(var(--blue-9));
}
.inbox-option-name {
  flex: 1;
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}
.inbox-option-type {
  @apply text-sm;
  color: rgb(var(--slate-8));
  background: rgb(var(--slate-4));
  padding: 2px 7px;
  border-radius: 20px;
}
.inbox-option-empty {
  padding: 14px 12px;
  @apply text-sm;
  color: rgb(var(--slate-9));
  display: flex;
  align-items: center;
  gap: 8px;
}

/* ─── Padronização do form do modal (igual ao "Nova consulta" / _form.scss) ─── */
/* Label caixa-normal, peso 500, slate-12, ícone alinhado por gap (antes era
   UPPERCASE/bold/slate-9 e destoava do resto do app). Scoped vence o global. */
.modal-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 0.875rem;
  font-weight: 500;
  text-transform: none;
  letter-spacing: normal;
  color: rgb(var(--slate-12));
  margin-bottom: 6px;
}
.modal-label i {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
  color: rgb(var(--slate-9));
}

/* Espaçamento vertical uniforme entre campos (≈ gap 16px do _form.scss). */
.modal-body > .modal-label {
  margin-top: 16px;
}
.modal-body > .modal-label:first-child {
  margin-top: 0;
}
.modal-body > .offset-field,
.modal-body > .svc-row-fields {
  margin-top: 16px;
}

/* Ícone + Cor lado a lado. A classe original vive (escopada) no
   SettingsTabServices, então aqui não existia → os dois campos empilhavam
   colados verticalmente. */
.svc-row-fields {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.svc-row-fields .modal-label {
  margin-top: 0;
}

/* ─── Editor de mensagem com destaque de variáveis ───
   O textarea fica com texto transparente + caret visível; atrás, um backdrop
   de MESMA métrica renderiza o texto e colore os {placeholders} igual aos
   chips de variáveis. Altura menor (140px) que os 300px anteriores. */
.msg-editor {
  position: relative;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  transition: border-color 0.15s, background 0.15s;
}
.msg-editor:focus-within {
  border-color: rgb(var(--blue-9));
  background: rgb(var(--slate-1));
}
.msg-editor-backdrop,
.msg-editor-input {
  margin: 0;
  border: 0;
  padding: 10px 12px;
  width: 100%;
  min-height: 140px;
  max-height: 320px;
  box-sizing: border-box;
  font-family: inherit;
  font-size: 0.875rem;
  font-weight: 500;
  line-height: 1.6;
  letter-spacing: normal;
  white-space: pre-wrap;
  word-break: break-word;
  overflow-wrap: break-word;
  tab-size: 4;
}
.msg-editor-backdrop {
  position: absolute;
  inset: 0;
  overflow: hidden;
  pointer-events: none;
  user-select: none;
  color: rgb(var(--slate-12));
}
.msg-editor-input {
  position: relative;
  display: block;
  background: transparent;
  color: transparent;
  caret-color: rgb(var(--slate-12));
  resize: vertical;
  outline: none;
}
.msg-editor-input::placeholder {
  color: rgb(var(--slate-8));
}
/* v-html não recebe o data-v do scoped → :deep alcança o span. Só color/bg
   (não altera métrica) pra não desalinhar o caret com o texto transparente. */
.msg-editor-backdrop :deep(.msg-var) {
  color: #4338ca;
  background: rgba(99, 102, 241, 0.14);
  border-radius: 3px;
}
:root.dark .msg-editor-backdrop :deep(.msg-var) {
  color: #a5b4fc;
  background: rgba(99, 102, 241, 0.22);
}

/* ───────── LOCK PANEL ───────── */
.lock-panel {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 12px;
  padding: 16px 20px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.lock-panel-header {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}
.lock-panel-icon {
  width: 18px;
  height: 18px;
  color: rgb(var(--blue-9));
  flex-shrink: 0;
  margin-top: 2px;
}
/* ───────── AVAILABILITY RULES (RIGHT SIDEBAR) ───────── */
.availability-rules-compact {
  display: flex;
  flex-direction: column;
}


/* ─── Skeleton Loading ─── */
@keyframes shimmer {
  0% {
    background-position: -400px 0;
  }
  100% {
    background-position: 400px 0;
  }
}

.notif-card-skeleton {
  pointer-events: none;
  overflow: hidden;
}

.skeleton-head {
  display: flex;
  align-items: center;
  gap: 12px;
}

.skeleton-icon {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: linear-gradient(
    90deg,
    rgb(var(--slate-4)) 25%,
    rgb(var(--slate-5)) 50%,
    rgb(var(--slate-4)) 75%
  );
  background-size: 400px 100%;
  animation: shimmer 1.4s infinite;
  flex-shrink: 0;
}

.skeleton-lines {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.skeleton-line {
  height: 12px;
  border-radius: 6px;
  background: linear-gradient(
    90deg,
    rgb(var(--slate-4)) 25%,
    rgb(var(--slate-5)) 50%,
    rgb(var(--slate-4)) 75%
  );
  background-size: 400px 100%;
  animation: shimmer 1.4s infinite;
}

.skeleton-line-lg {
  width: 70%;
}
.skeleton-line-sm {
  width: 45%;
}
.skeleton-line-full {
  width: 100%;
}

/* ─── Empty State ─── */
.notif-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  flex: 1;
  padding: 60px 20px;
  text-align: center;
  gap: 10px;
}
.notif-empty-ico {
  width: 40px;
  height: 40px;
  color: rgb(var(--slate-7));
  margin-bottom: 8px;
}
.notif-empty-title {
  font-size: 16px;
  font-weight: 700;
  color: rgb(var(--slate-11));
  margin: 0;
}
.notif-empty-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0;
}

/* ─── Logs Panel ─── */
.logs-panel {
  margin-top: 28px;
  border: 1px solid rgb(var(--slate-5));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-2));
}
.logs-panel-toggle {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 13px 16px;
  background: none;
  border: none;
  cursor: pointer;
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-11));
  text-align: left;
  transition: background 0.15s;
}
.logs-panel-toggle:hover {
  background: rgb(var(--slate-3));
}
.logs-chevron {
  transition: transform 0.2s;
}
.logs-chevron.open {
  transform: rotate(180deg);
}

.logs-body {
  border-top: 1px solid rgb(var(--slate-5));
  padding: 14px 16px;
}
.logs-filters {
  display: flex;
  gap: 8px;
  margin-bottom: 12px;
}
/* Definição duplicada legada — neutralizada (ver bloco acima). Mantém só o
   flex pra não reintroduzir a caixa em cima do FormSelect. */
.logs-filter-select {
  flex: 1;
  min-width: 0;
}
.logs-refresh-btn:hover {
  background: rgb(var(--slate-3));
}
.logs-refresh-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.logs-loading {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 20px;
  color: rgb(var(--slate-9));
  @apply text-sm;
}
.logs-empty {
  padding: 20px;
  text-align: center;
  @apply text-sm;
  color: rgb(var(--slate-9));
}

/* Tabela */
.logs-table {
  width: 100%;
  border-collapse: collapse;
  @apply text-sm;
}
.logs-table th {
  padding: 7px 10px;
  text-align: left;
  font-weight: 600;
  color: rgb(var(--slate-9));
  border-bottom: 1px solid rgb(var(--slate-5));
  @apply text-sm;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.logs-table td {
  padding: 9px 10px;
  border-bottom: 1px solid rgb(var(--slate-4));
  color: rgb(var(--slate-11));
  vertical-align: middle;
}
.logs-table tbody tr:last-child td {
  border-bottom: none;
}
.logs-table tbody tr:hover td {
  background: rgb(var(--slate-3));
}
.log-row-failed td {
  background: rgba(239, 68, 68, 0.03);
}

.log-rule-name {
  display: flex;
  align-items: center;
  gap: 6px;
  font-weight: 500;
}
.log-rule-ico {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
}
.log-event-title {
  max-width: 180px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.log-date {
  white-space: nowrap;
  color: rgb(var(--slate-9));
  @apply text-sm;
}

/* Badges de status */
.log-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 20px;
  @apply text-sm;
  font-weight: 600;
  text-transform: uppercase;
}
.log-badge-sent {
  background: rgba(34, 197, 94, 0.12);
  color: #16a34a;
}
.log-badge-failed {
  background: rgba(239, 68, 68, 0.12);
  color: #dc2626;
}
.log-badge-skipped {
  background: rgba(148, 163, 184, 0.15);
  color: rgb(var(--slate-9));
}

/* Paginação */
.logs-pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  margin-top: 12px;
  padding-top: 10px;
  border-top: 1px solid rgb(var(--slate-4));
}
.logs-page-btn {
  width: 28px;
  height: 28px;
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  background: rgb(var(--slate-1));
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgb(var(--slate-10));
  transition: background 0.15s;
}
.logs-page-btn:hover:not(:disabled) {
  background: rgb(var(--slate-3));
}
.logs-page-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
.logs-page-info {
  @apply text-sm;
  color: rgb(var(--slate-9));
}

</style>
