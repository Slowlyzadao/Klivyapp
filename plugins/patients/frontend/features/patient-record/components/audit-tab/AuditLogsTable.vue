<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { formatProfRole } from '@plugins/patients/frontend/features/patient-record/utils/professionalRoles';
import {
  BRT,
  auditActionConfig,
  RESOURCE_TYPE_LABELS,
} from '@plugins/patients/frontend/constants/audit';

defineProps({
  logs: { type: Array, default: () => [] },
  expanded: { type: Set, default: () => new Set() },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle-details']);

const { t } = useI18n();
const store = useStore();

const agentsById = computed(() => {
  const list = store.getters['agents/getAgents'] || [];
  return list.reduce((acc, a) => {
    acc[a.id] = a;
    return acc;
  }, {});
});

const actorAvatarUrl = log => {
  const agent = agentsById.value[log.actor_id];
  return agent?.avatar_url || agent?.thumbnail || '';
};

const getInitials = name => {
  if (!name) return '';
  return name.charAt(0).toUpperCase();
};

const formatDateTime = isoStr => {
  if (!isoStr) return '—';
  const d = new Date(isoStr);
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: BRT,
  });
};

// Renderiza valores não-diff (objeto/hash em changed_fields).
// Usado pelo `clinical_override` (Roadmap #16.1) — formato
// `{ reason, source, target_action }` em vez de [old, new].
const formatChangeMeta = value => {
  const empty = t('PATIENT_AUDIT.TABLE.EMPTY_VALUE');
  if (value === null || value === undefined) return empty;
  if (typeof value !== 'object') return String(value);
  return Object.entries(value)
    .map(([k, v]) => {
      const display = v === null || v === undefined ? empty : String(v);
      return `${k}: ${display}`;
    })
    .join(' · ');
};

// Mapeia action → translation key + parâmetros.
const ACTION_TEXT_KEYS = {
  view: 'PATIENT_AUDIT.ACTION_TEXT.VIEW',
  create: 'PATIENT_AUDIT.ACTION_TEXT.CREATE',
  update: 'PATIENT_AUDIT.ACTION_TEXT.UPDATE',
  delete: 'PATIENT_AUDIT.ACTION_TEXT.DELETE',
  sign: 'PATIENT_AUDIT.ACTION_TEXT.SIGN',
  finalize: 'PATIENT_AUDIT.ACTION_TEXT.FINALIZE',
  approve: 'PATIENT_AUDIT.ACTION_TEXT.APPROVE',
  export: 'PATIENT_AUDIT.ACTION_TEXT.EXPORT',
  pay: 'PATIENT_AUDIT.ACTION_TEXT.PAY',
  print: 'PATIENT_AUDIT.ACTION_TEXT.PRINT',
  clinical_override: 'PATIENT_AUDIT.ACTION_TEXT.CLINICAL_OVERRIDE',
};

const generateDetailedAuditText = log => {
  const actor = log.actor_name
    ? t('PATIENT_AUDIT.ACTION_TEXT.ACTOR_PREFIX_USER', { actor: log.actor_name })
    : t('PATIENT_AUDIT.ACTION_TEXT.ACTOR_PREFIX_SYSTEM');
  const resource =
    RESOURCE_TYPE_LABELS[log.resource_type] || log.resource_type || 'Prontuário';
  const key = ACTION_TEXT_KEYS[log.action];
  if (key) return t(key, { actor, resource });
  return t('PATIENT_AUDIT.ACTION_TEXT.DEFAULT', {
    actor,
    resource,
    action: log.action,
  });
};
</script>

<template>
  <div class="aud-table-wrap">
    <div v-if="isLoading" class="aud-loading">
      <i class="i-lucide-loader-2 animate-spin w-5 h-5" />
      <span>{{ t('PATIENT_AUDIT.TABLE.LOADING') }}</span>
    </div>

    <div v-else class="overflow-x-auto">
      <table class="aud-table">
        <thead>
          <tr class="aud-thead-row">
            <th class="aud-th">{{ t('PATIENT_AUDIT.TABLE.COL_DATE') }}</th>
            <th class="aud-th">{{ t('PATIENT_AUDIT.TABLE.COL_ACTION') }}</th>
            <th class="aud-th">{{ t('PATIENT_AUDIT.TABLE.COL_USER') }}</th>
            <th class="aud-th">{{ t('PATIENT_AUDIT.TABLE.COL_MODULE') }}</th>
            <th class="aud-th">{{ t('PATIENT_AUDIT.TABLE.COL_IP') }}</th>
            <th class="aud-th aud-th--center">
              {{ t('PATIENT_AUDIT.TABLE.COL_INFO') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="logs.length === 0">
            <td colspan="6" class="aud-empty-cell">
              <div class="aud-empty-state">
                <i class="i-lucide-shield-off w-6 h-6" />
                <p>{{ t('PATIENT_AUDIT.TABLE.EMPTY') }}</p>
                <p class="aud-empty-hint">
                  {{ t('PATIENT_AUDIT.TABLE.EMPTY_HINT') }}
                </p>
              </div>
            </td>
          </tr>

          <template v-for="log in logs" :key="log.id">
            <tr class="aud-row">
              <td class="aud-td aud-td--mono aud-td--dim">
                {{ formatDateTime(log.occurred_at) }}
              </td>

              <td class="aud-td">
                <span
                  class="aud-action-badge"
                  :class="auditActionConfig(log.action).color"
                >
                  <i class="w-3 h-3" :class="auditActionConfig(log.action).icon" />
                  {{ auditActionConfig(log.action).label }}
                </span>
              </td>

              <td class="aud-td">
                <div class="aud-user-cell">
                  <img
                    v-if="actorAvatarUrl(log)"
                    :src="actorAvatarUrl(log)"
                    :alt="log.actor_name || 'Avatar'"
                    class="aud-avatar aud-avatar--img"
                  />
                  <div v-else class="aud-avatar">
                    {{ getInitials(log.actor_name) }}
                  </div>
                  <div class="aud-user-info">
                    <p class="aud-user-name">
                      {{
                        log.actor_name || t('PATIENT_AUDIT.TABLE.DEFAULT_USER')
                      }}
                    </p>
                    <span
                      v-if="log.actor_role"
                      class="aud-role-badge"
                      :class="`aud-role-badge--${log.actor_role.toLowerCase()}`"
                    >
                      {{ formatProfRole(log.actor_role) }}
                    </span>
                  </div>
                </div>
              </td>

              <td class="aud-td aud-td--details">
                <span class="aud-module-name">
                  {{
                    log.resource_type || t('PATIENT_AUDIT.TABLE.DEFAULT_MODULE')
                  }}
                </span>
                <span v-if="log.resource_id" class="aud-module-id">
                  #{{ log.resource_id }}
                </span>

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
                    <template v-if="Array.isArray(vals)">
                      <span class="aud-diff-field">{{ field }}:</span>
                      <span class="aud-diff-old">
                        {{
                          vals[0] !== null && vals[0] !== undefined
                            ? vals[0]
                            : t('PATIENT_AUDIT.TABLE.EMPTY_VALUE')
                        }}
                      </span>
                      <i
                        class="i-lucide-arrow-right w-2.5 h-2.5 text-slate-600"
                      />
                      <span class="aud-diff-new">
                        {{
                          vals[1] !== null && vals[1] !== undefined
                            ? vals[1]
                            : t('PATIENT_AUDIT.TABLE.EMPTY_VALUE')
                        }}
                      </span>
                    </template>
                    <template v-else>
                      <span class="aud-diff-field">{{ field }}:</span>
                      <span class="aud-diff-meta">
                        {{ formatChangeMeta(vals) }}
                      </span>
                    </template>
                  </div>
                </div>

                <div
                  v-else-if="log.new_value"
                  class="aud-snapshot"
                  :title="JSON.stringify(log.new_value)"
                >
                  {{ JSON.stringify(log.new_value).slice(0, 80)
                  }}{{
                    JSON.stringify(log.new_value).length > 80 ? '…' : ''
                  }}
                </div>
              </td>

              <td class="aud-td aud-td--mono aud-td--dim">
                {{ log.ip_address || '—' }}
              </td>

              <td class="aud-td aud-td--center">
                <BeclinicButton
                  size="sm"
                  variant="ghost"
                  color="slate"
                  :icon="
                    expanded.has(log.id) ? 'i-lucide-eye-off' : 'i-lucide-eye'
                  "
                  :title="
                    expanded.has(log.id)
                      ? t('PATIENT_AUDIT.TABLE.COLLAPSE_TITLE')
                      : t('PATIENT_AUDIT.TABLE.EXPAND_TITLE')
                  "
                  @click="emit('toggle-details', log.id)"
                />
              </td>
            </tr>

            <tr v-if="expanded.has(log.id)" class="aud-expanded-row">
              <td colspan="6" class="aud-expanded-cell">
                <div class="aud-expanded-body">
                  <i class="i-lucide-info w-4 h-4 aud-expanded-icon" />
                  <div>
                    <p class="aud-expanded-title">
                      {{ t('PATIENT_AUDIT.EXPANDED.TITLE') }}
                    </p>
                    <p class="aud-expanded-text">
                      {{ generateDetailedAuditText(log) }}
                    </p>

                    <div
                      v-if="
                        log.action === 'update' &&
                        log.changed_fields &&
                        Object.keys(log.changed_fields).length > 0
                      "
                      class="aud-expanded-diff"
                    >
                      <p class="aud-expanded-diff-title">
                        {{ t('PATIENT_AUDIT.EXPANDED.DIFF_TITLE') }}
                      </p>
                      <ul class="aud-expanded-diff-list">
                        <li
                          v-for="(vals, field) in log.changed_fields"
                          :key="field"
                          class="aud-expanded-diff-item"
                        >
                          <span class="aud-diff-f">{{ field }}</span>
                          <span class="aud-diff-o">
                            {{
                              vals[0] !== null
                                ? vals[0]
                                : t('PATIENT_AUDIT.EXPANDED.NULL_VALUE')
                            }}
                          </span>
                          <i
                            class="i-lucide-arrow-right w-3 h-3 text-slate-600"
                          />
                          <span class="aud-diff-n">
                            {{
                              vals[1] !== null
                                ? vals[1]
                                : t('PATIENT_AUDIT.EXPANDED.NULL_VALUE')
                            }}
                          </span>
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
</template>
