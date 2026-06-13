<script setup>
/**
 * Backups — v2 (canon F-32 versão "lite").
 *
 * Read-only: lista os dumps que o Easypanel / Postgres já geram em
 * `/app/storage/postgres-backups` (configurável via env
 * FINANCIAL_BACKUP_PATH). Não duplicamos o pg_dump+cron+S3 do canon
 * porque a infra do Easypanel já entrega isso.
 *
 * O que mostramos:
 *   • Lista dos dumps presentes (nome, tamanho, idade em dias).
 *   • Diagnóstico de retenção (mais antigo / mais recente).
 *   • Aviso claro se o diretório não está configurado.
 *
 * O que NÃO fazemos (intencional):
 *   • Download direto (dump tem dados sensíveis — paciente, financeiro,
 *     segredos do banco).
 *   • Restauração via UI (operação crítica que mora em SSH/Easypanel).
 *
 * Permissão: ADMIN/AUDITOR (backend valida).
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import FinancialV2 from '../api/financialV2';
import '@plugins/financial/frontend/styles/financial.scss';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const data = ref([]);
const meta = ref({});
const loading = ref(false);

// Disparo manual ("Backup agora") — útil antes de migrations arriscadas
// ou pra validar a infra.
const showRunConfirm = ref(false);
const running = ref(false);

// Exclusão manual de backup (local + R2). Útil pra limpar dumps antigos
// ou corrompidos sem esperar o cron de retenção.
const showDeleteConfirm = ref(false);
const fileToDelete = ref(null);
const deleting = ref(false);

function askDelete(file) {
  fileToDelete.value = file;
  showDeleteConfirm.value = true;
}

async function confirmDelete() {
  const file = fileToDelete.value;
  if (!file) return;
  deleting.value = true;
  try {
    const { data: response } = await FinancialV2.backups.destroyBackup(file.name);
    showDeleteConfirm.value = false;
    fileToDelete.value = null;
    const where = [];
    if (response.deleted?.local) where.push('local');
    if (response.deleted?.r2) where.push('R2');
    notifySuccess(`Backup excluído de: ${where.join(', ')}.`);
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao excluir backup.');
  } finally {
    deleting.value = false;
  }
}

function askRun() { showRunConfirm.value = true; }

async function confirmRun() {
  running.value = true;
  try {
    const { data: response } = await FinancialV2.backups.run();
    showRunConfirm.value = false;
    notifySuccess(
      `Backup criado: ${response.file} (${Math.round(response.size_bytes / 1024)} KB em ${response.duration_seconds}s).`
    );
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao criar backup. Verifique se pg_dump está disponível no container.');
  } finally {
    running.value = false;
  }
}

async function load() {
  loading.value = true;
  try {
    const { data: response } = await FinancialV2.backups.index();
    data.value = response?.data || [];
    meta.value = response?.meta || {};
  } catch (err) {
    notifyError(err?.response?.data?.error === 'forbidden'
      ? 'Acesso negado. Apenas ADMIN/AUDITOR podem ver backups.'
      : 'Falha ao listar backups.');
  } finally {
    loading.value = false;
  }
}

// Helpers para badge de fonte (Local/R2/Ambos).
function sourceBadge(sources) {
  const set = new Set(sources || []);
  if (set.has('local') && set.has('r2')) return { label: 'Local + R2', color: 'emerald', icon: 'i-lucide-cloud-check' };
  if (set.has('r2')) return { label: 'R2', color: 'blue', icon: 'i-lucide-cloud' };
  return { label: 'Local', color: 'slate', icon: 'i-lucide-hard-drive' };
}

onMounted(load);

function formatDateTimeBR(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

// Saúde: se o backup mais recente é > 2 dias, status crítico (canon: diário).
const healthStatus = computed(() => {
  const localOk = meta.value.local?.configured;
  if (!localOk && !meta.value.r2?.configured) {
    return { color: 'amber', label: 'Não configurado', tone: 'warn' };
  }
  if (!data.value.length) return { color: 'ruby', label: 'Nenhum backup', tone: 'critical' };
  const newest = meta.value.newest_days ?? 999;
  if (newest > 2) return { color: 'ruby', label: `Último há ${newest} dias`, tone: 'critical' };
  if (newest > 1) return { color: 'amber', label: `Último há ${newest} dia(s)`, tone: 'warn' };
  return { color: 'emerald', label: 'Em dia', tone: 'ok' };
});

// R2 sync KPI: quantos arquivos estão tanto em local quanto em R2.
const r2SyncStatus = computed(() => {
  if (!meta.value.r2?.configured) {
    return { label: 'R2 não configurado', color: 'slate', detail: 'set STORAGE_* envs' };
  }
  const synced = data.value.filter(f => (f.sources || []).includes('r2')).length;
  const total = data.value.length;
  if (total === 0) return { label: '—', color: 'slate', detail: 'nenhum backup' };
  if (synced === total) return { label: `${synced}/${total}`, color: 'emerald', detail: 'tudo em R2' };
  if (synced === 0) return { label: `0/${total}`, color: 'ruby', detail: 'nenhum em R2' };
  return { label: `${synced}/${total}`, color: 'amber', detail: 'parcial' };
});

// PR audit 2026-05-21: `embedded=true` esconde o header próprio quando esta
// page é renderizada como tab dentro de SettingsV2 (evita duplicação com o
// header "Configurações financeiras"). Ver SettingsV2.vue para contexto.
defineProps({ embedded: { type: Boolean, default: false } });
</script>

<template>
  <div class="finv2-page" :class="{ 'finv2-page--embedded': embedded }">
    <header v-if="!embedded" class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Backups</h1>
        <p class="finv2-page__subtitle">
          Lista dos dumps de banco gerados pelo Easypanel/Postgres.
          A geração e retenção são responsabilidade da infra externa
          (canon F-32 §"armazenado fora do servidor principal").
        </p>
      </div>
      <div class="finv2-page__header-actions">
        <BeclinicButton
          variant="faded"
          color="slate"
          icon="i-lucide-refresh-cw"
          label="Atualizar"
          size="sm"
          :is-loading="loading"
          @click="load"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-database-backup"
          label="Backup agora"
          size="sm"
          :is-loading="running"
          @click="askRun"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- KPIs / status -->
      <div class="finv2-kpis">
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-shield-check w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Saúde</span>
            <Badge
              :label="healthStatus.label"
              :color="healthStatus.color"
              size="sm"
            />
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-database w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Total de backups</span>
            <strong class="finv2-kpi__value">{{ meta.total ?? 0 }}</strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-hard-drive w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Tamanho total</span>
            <strong class="finv2-kpi__value">{{ meta.total_size_human || '—' }}</strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-cloud w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Sync R2</span>
            <Badge
              :label="r2SyncStatus.label"
              :color="r2SyncStatus.color"
              size="sm"
            />
            <span class="bkp-v2__kpi-hint">{{ r2SyncStatus.detail }}</span>
          </div>
        </div>
      </div>

      <!-- Storage info: local + R2 -->
      <div class="bkp-v2__storage-row">
        <div class="bkp-v2__path">
          <i class="i-lucide-hard-drive w-3.5 h-3.5" />
          <strong>Local:</strong>
          <code>{{ meta.local?.path || '—' }}</code>
          <span class="bkp-v2__path-meta">
            {{ meta.local?.count ?? 0 }} arquivo(s)
          </span>
        </div>
        <div class="bkp-v2__path">
          <i class="i-lucide-cloud w-3.5 h-3.5" />
          <strong>R2:</strong>
          <template v-if="meta.r2?.configured">
            <code>{{ meta.r2.bucket }}</code>
            <span class="bkp-v2__path-meta">
              {{ meta.r2.count ?? 0 }} arquivo(s)
            </span>
          </template>
          <span v-else class="bkp-v2__path-warn">
            não configurado (set STORAGE_* envs)
          </span>
        </div>
      </div>

      <!-- Lista -->
      <div v-if="loading" class="finv2-state">
        <div class="finv2-spinner" /><span>Carregando…</span>
      </div>
      <div v-else-if="meta.configured && data.length === 0" class="finv2-state">
        <div class="finv2-state__icon-wrap"><i class="i-lucide-database w-7 h-7" /></div>
        <p class="finv2-state__title">Nenhum dump encontrado</p>
        <p class="finv2-state__hint">
          O diretório existe mas está vazio. Verifique a configuração
          do backup automático no Easypanel.
        </p>
      </div>
      <div v-else-if="data.length > 0" class="finv2-table-wrap">
        <table class="finv2-table">
          <thead>
            <tr>
              <th>Arquivo</th>
              <th>Onde está</th>
              <th>Tamanho</th>
              <th>Data</th>
              <th>Idade</th>
              <th class="bkp-v2__th-actions">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="f in data" :key="f.name">
              <td>
                <div class="bkp-v2__file-cell">
                  <i class="i-lucide-file-archive w-4 h-4 bkp-v2__file-icon" />
                  <strong>{{ f.name }}</strong>
                </div>
              </td>
              <td>
                <Badge
                  :label="sourceBadge(f.sources).label"
                  :color="sourceBadge(f.sources).color"
                  :icon="sourceBadge(f.sources).icon"
                  size="xs"
                />
              </td>
              <td class="finv2-table__td-num">{{ f.size_human }}</td>
              <td class="finv2-table__td-date">{{ formatDateTimeBR(f.modified_at) }}</td>
              <td>
                <Badge
                  :label="`${f.age_days}d`"
                  :color="f.age_days > 2 ? 'amber' : 'emerald'"
                  size="xs"
                />
              </td>
              <td class="bkp-v2__td-actions">
                <Tooltip label="Excluir backup">
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-trash-2"
                    @click="askDelete(f)"
                  />
                </Tooltip>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Nota de operação (rodapé) -->
      <div class="bkp-v2__note">
        <i class="i-lucide-info w-3.5 h-3.5" />
        <span>
          <strong>Restauração e download</strong> não estão disponíveis pela
          interface — operações de restauração são feitas via SSH (decisão de
          segurança: dump contém dados sensíveis).
          <br>
          Cron diário às <strong>03:00 UTC</strong> via Sidekiq.
          Retenção: <strong>local 7 dias</strong>, <strong>R2 30 dias</strong>.
        </span>
      </div>
    </div>

    <!-- Confirmação "Backup agora" — operação síncrona, pode levar segundos
         a poucos minutos dependendo do tamanho do banco. -->
    <ConfirmDangerModal
      v-model:show="showRunConfirm"
      title="Disparar backup agora?"
      :message="`Será executado pg_dump → arquivo local em ${meta.local?.path || 'storage/postgres-backups'}${meta.r2?.configured ? ' → upload pra R2 (' + meta.r2.bucket + ')' : ''}. A operação é síncrona, pode levar alguns minutos dependendo do tamanho do banco. Continuar?`"
      confirm-label="Disparar backup"
      :loading="running"
      @confirm="confirmRun"
    />

    <!-- Confirmação de exclusão de backup -->
    <ConfirmDangerModal
      v-model:show="showDeleteConfirm"
      title="Excluir este backup?"
      :message="fileToDelete
        ? `O arquivo '${fileToDelete.name}' (${fileToDelete.size_human}) será removido${(fileToDelete.sources || []).length > 1 ? ' de TODAS as fontes (Local + R2)' : ' de ' + (fileToDelete.sources || ['local']).join('+')}. Sem afetar o banco em si — só o dump. Não dá pra desfazer.`
        : ''"
      confirm-label="Excluir backup"
      :loading="deleting"
      @confirm="confirmDelete"
    />
  </div>
</template>

<style scoped lang="scss">
.bkp-v2__storage-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
@media (max-width: 720px) { .bkp-v2__storage-row { grid-template-columns: 1fr; } }

.bkp-v2__path {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  font-size: 12px;
  color: rgb(var(--slate-11));
  flex-wrap: wrap;
  code {
    background: rgb(var(--slate-3));
    padding: 1px 6px;
    border-radius: 4px;
    font-family: 'SF Mono', Menlo, monospace;
    color: rgb(var(--slate-12));
  }
}
.bkp-v2__path-warn { color: rgb(var(--amber-11)); }
.bkp-v2__path-meta {
  margin-left: auto;
  color: rgb(var(--slate-9));
  font-size: 11.5px;
  font-variant-numeric: tabular-nums;
}

.bkp-v2__kpi-hint {
  font-size: 11px;
  color: rgb(var(--slate-9));
  margin-top: 2px;
}

.bkp-v2__warning {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 14px 16px;
  border-radius: 10px;
  background: rgba(245, 158, 11, 0.10);
  border: 1px solid rgba(245, 158, 11, 0.32);
  border-left: 3px solid #f59e0b;
  color: rgb(var(--slate-12));
  font-size: 13px;
  strong { color: rgb(var(--amber-11)); font-weight: 600; }
  p { margin: 4px 0 0; color: rgb(var(--slate-11)); }
  code {
    background: rgb(var(--slate-2));
    padding: 1px 5px;
    border-radius: 4px;
    font-family: 'SF Mono', Menlo, monospace;
    font-size: 11.5px;
  }
}
.bkp-v2__warning-hint { font-size: 12px; }

.bkp-v2__file-cell {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.bkp-v2__file-icon { color: rgb(var(--slate-9)); }

.bkp-v2__th-actions { width: 80px; text-align: right; }
.bkp-v2__td-actions { text-align: right; white-space: nowrap; }

.bkp-v2__note {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  padding: 10px 12px;
  border-radius: 8px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  font-size: 12px;
  color: rgb(var(--slate-9));
  line-height: 1.5;
  strong { color: rgb(var(--slate-12)); }
  i { margin-top: 2px; flex-shrink: 0; }
}
</style>
