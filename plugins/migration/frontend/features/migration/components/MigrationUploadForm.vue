<script setup>
import { ref, computed, watch } from 'vue';
import {
  uploadCsv,
  previewCsv,
  fetchProfessionalUsers,
  fetchFinancialSettings,
} from '../api/migrationApi.js';

const props = defineProps({
  accounts: { type: Array, required: true },
});
const emit = defineEmits(['runCreated']);

const accountId = ref(null);
const kind      = ref('patients');
const source    = ref('clinicorp');

// Single-file flow (agenda etc)
const file      = ref(null);

// Multi-file flow (patients): Patient.csv + PatientAnamnesis.csv + Anamnesis.csv
const patientsFile         = ref(null);
const patientAnamnesisFile = ref(null);
const anamnesisFile        = ref(null);

// treatment_operations flow: 1 arquivo (TreatmentOperation.csv/.xlsx) +
// passo de mapeamento de dentistas que vem da pré-visualização.
const operationsFile = ref(null);
const dentistMapping = ref({}); // { "DentistName ou DentistId" => user_id|"ignore" }
const professionalUsers = ref([]); // lista vinda do backend
const loadingUsers = ref(false);

// financial flow (F-10): Budgets.csv + PaymentHeader.csv + PaymentItem.csv +
// passo de mapeamento de dentistas (só Budgets tem DentistId/DentistName) +
// estratégia de conta bancária ('create' nova "Importação Clinicorp" ou 'existing'
// — admin pode escolher conta específica via bankAccountId).
// `paymentMethodMapping` (canon V2): { 'pix' => 42, 'credito' => 43 } — admin
// escolhe PaymentMethod do Settings pra cada kind canônico encontrado nos CSVs.
// Kinds sem mapping caem em fallback: importer auto-cria "Importação Clinicorp · X".
const budgetsFile           = ref(null);
const paymentHeadersFile    = ref(null);
const paymentItemsFile      = ref(null);
const bankAccountStrategy   = ref('create');
const bankAccountId         = ref(null);
const paymentMethodMapping  = ref({}); // { kind => pm_id|'' }
const specialtyMapping      = ref({}); // { 'Cirurgia' => dre_id|'' }
const financialSettings     = ref({ payment_methods: [], bank_accounts: [], dre_categories: [] });
const loadingFinancial      = ref(false);

const previewing = ref(false);
const submitting = ref(false);
const preview    = ref(null); // { summary, rows, warnings, anamneses?, dentists? }
const errorMsg   = ref('');
const successMsg = ref('');

const KINDS = [
  { value: 'patients',             label: 'Pacientes (+ anamnese opcional)' },
  { value: 'agenda',               label: 'Agenda (eventos / appointments)' },
  { value: 'treatment_operations', label: 'Operações / Procedimentos (TreatmentOperation)' },
  { value: 'financial',            label: 'Financeiro (Budgets + PaymentHeader + PaymentItem)' },
];

const SOURCES = [
  { value: 'clinicorp', label: 'Clinicorp (CSV)' },
  { value: 'generic',   label: 'Genérico (CSV padrão Klivy)', disabled: true },
];

const isPatients   = computed(() => kind.value === 'patients');
const isOperations = computed(() => kind.value === 'treatment_operations');
const isFinancial  = computed(() => kind.value === 'financial');

const canPreview = computed(() => {
  if (!accountId.value || !kind.value || previewing.value || submitting.value) return false;
  if (isPatients.value)   return !!patientsFile.value;
  if (isOperations.value) return !!operationsFile.value;
  if (isFinancial.value)  return !!budgetsFile.value && !!paymentHeadersFile.value && !!paymentItemsFile.value;
  return false;
});

const canSubmit = computed(() => {
  if (!accountId.value || !kind.value || submitting.value) return false;
  if (isPatients.value)   return !!patientsFile.value;
  if (isOperations.value) {
    // Exige preview com dentistas mapeados antes de iniciar — o admin precisa
    // ter visto o passo de mapeamento. `dentists.length===0` é raro mas pode
    // acontecer (XLSX vazio); aí libera direto.
    return !!operationsFile.value && !!preview.value;
  }
  if (isFinancial.value) {
    // Mesma regra: exige preview com revisão (dentistas + estratégia de conta).
    return !!budgetsFile.value && !!paymentHeadersFile.value && !!paymentItemsFile.value && !!preview.value;
  }
  return !!file.value;
});

// Aceita .csv direto ou .xlsx/.xls (converte pra CSV no client via SheetJS).
// Backend permanece processando string CSV — sem nova gem Ruby.
const XLSX_EXTENSIONS = ['.xlsx', '.xls', '.xlsm', '.xlsb', '.ods'];

const isSpreadsheet = filename =>
  XLSX_EXTENSIONS.some(ext => filename.toLowerCase().endsWith(ext));

async function convertXlsxToCsv(file) {
  // Lazy import — ~600KB minified, só carrega se o user de fato submeter XLSX
  const { read, utils } = await import('xlsx');
  const buffer = await file.arrayBuffer();
  const wb = read(buffer, { type: 'array' });
  const sheetName = wb.SheetNames[0];
  const sheet = wb.Sheets[sheetName];
  if (!sheet) throw new Error(`Planilha vazia ou sem aba ativa.`);
  // `rawNumbers: true` força SheetJS a escrever String(num) em vez de aplicar
  // formato Excel — sem isso, IDs longos do Clinicorp (16 dígitos, ex.
  // 5922847262244865) saem em notação científica EN-US ("5.92285E+15")
  // perdendo precisão. Causa raiz da importação Streit 2026-05-21 que
  // deixou 469 anamneses órfãs no preview porque a chave "5.92285E+15"
  // gerada aqui não casava com a chave "5,92285E+15" (PT-BR com vírgula)
  // que o importer Ruby tentava reconstruir via `scientific_truncation`.
  // Com rawNumbers:true os IDs ficam exatos pra todos os pacientes ≤ 2^53
  // (~9 quadrilhões), que cobre 100% dos IDs Clinicorp vistos até hoje.
  const csv = utils.sheet_to_csv(sheet, { FS: ',', strip: false, rawNumbers: true });
  const csvName = file.name.replace(/\.(xlsx|xls|xlsm|xlsb|ods)$/i, '.csv');
  return new File([csv], csvName, { type: 'text/csv' });
}

const converting = ref(false);

async function pickFile(e, slot) {
  const f = e.target.files?.[0];
  if (!f) return;

  let resolved = f;
  if (isSpreadsheet(f.name)) {
    converting.value = true;
    errorMsg.value = '';
    try {
      resolved = await convertXlsxToCsv(f);
    } catch (err) {
      errorMsg.value = `Falha ao ler planilha "${f.name}": ${err.message || err}`;
      // Reset input para permitir o user tentar de novo com o mesmo arquivo
      e.target.value = '';
      converting.value = false;
      return;
    } finally {
      converting.value = false;
    }
  }

  if (slot === 'file') file.value = resolved;
  else if (slot === 'patients') patientsFile.value = resolved;
  else if (slot === 'patientAnamnesis') patientAnamnesisFile.value = resolved;
  else if (slot === 'anamnesis') anamnesisFile.value = resolved;
  else if (slot === 'operations') operationsFile.value = resolved;
  else if (slot === 'budgets') budgetsFile.value = resolved;
  else if (slot === 'paymentHeaders') paymentHeadersFile.value = resolved;
  else if (slot === 'paymentItems') paymentItemsFile.value = resolved;
  // Any file change invalidates a previously-computed preview
  preview.value = null;
}

// Carrega a lista de usuários da conta quando o admin escolhe a combinação
// (account + kind ∈ {treatment_operations, financial}). Roda toda vez que
// (account, kind) mudam — usuários são por-conta, então mudar de conta DEVE
// invalidar a lista.
watch([accountId, kind], async ([acc, k], [prevAcc] = []) => {
  const needsUsers = k === 'treatment_operations' || k === 'financial';
  // Se tirou a combinação válida, descarta a lista carregada.
  if (!acc || !needsUsers) {
    if (acc !== prevAcc) professionalUsers.value = [];
    return;
  }
  // Sempre recarrega quando entra na combinação válida — não cacheia entre
  // contas distintas pra evitar mostrar usuário da conta errada.
  loadingUsers.value = true;
  try {
    const res = await fetchProfessionalUsers(acc);
    professionalUsers.value = res.users || [];
  } catch (err) {
    errorMsg.value = `Falha ao carregar usuários: ${err.message || err}`;
  } finally {
    loadingUsers.value = false;
  }
});

// Settings financeiros (PaymentMethods + BankAccounts) — só pro kind=financial.
// Carregados quando (account, kind=financial) muda. Invalida ao trocar de conta
// (PaymentMethods são por-conta) e ao sair do fluxo financeiro.
watch([accountId, kind], async ([acc, k], [prevAcc, prevKind] = []) => {
  if (k !== 'financial' || !acc) {
    if (prevKind === 'financial' && (acc !== prevAcc || k !== 'financial')) {
      financialSettings.value = { payment_methods: [], bank_accounts: [], dre_categories: [] };
      paymentMethodMapping.value = {};
      specialtyMapping.value = {};
      bankAccountId.value = null;
    }
    return;
  }
  loadingFinancial.value = true;
  try {
    const res = await fetchFinancialSettings(acc);
    financialSettings.value = {
      payment_methods: res.payment_methods || [],
      bank_accounts: res.bank_accounts || [],
      dre_categories: res.dre_categories || [],
    };
  } catch (err) {
    errorMsg.value = `Falha ao carregar formas de pagamento: ${err.message || err}`;
  } finally {
    loadingFinancial.value = false;
  }
});

function buildArgs() {
  const args = { accountId: accountId.value, kind: kind.value, source: source.value };
  if (isPatients.value) {
    args.files = {
      patients: patientsFile.value,
      patientAnamnesis: patientAnamnesisFile.value,
      anamnesis: anamnesisFile.value,
    };
  } else if (isOperations.value) {
    args.files = { operations: operationsFile.value };
    args.dentistMapping = dentistMapping.value;
  } else if (isFinancial.value) {
    args.files = {
      budgets: budgetsFile.value,
      paymentHeaders: paymentHeadersFile.value,
      paymentItems: paymentItemsFile.value,
    };
    args.dentistMapping = dentistMapping.value;
    args.bankAccountStrategy = bankAccountStrategy.value;
    args.bankAccountId = bankAccountId.value;
    args.paymentMethodMapping = paymentMethodMapping.value;
    args.specialtyMapping = specialtyMapping.value;
  } else {
    args.file = file.value;
  }
  return args;
}

async function runPreview() {
  errorMsg.value = '';
  successMsg.value = '';
  preview.value = null;
  if (!canPreview.value) return;
  previewing.value = true;
  try {
    preview.value = await previewCsv(buildArgs());
  } catch (err) {
    errorMsg.value = err.message || 'Falha ao gerar pré-visualização.';
  } finally {
    previewing.value = false;
  }
}

async function submit() {
  errorMsg.value = '';
  successMsg.value = '';
  if (!canSubmit.value) return;
  submitting.value = true;
  try {
    const run = await uploadCsv(buildArgs());
    successMsg.value = `Migração #${run.id} enfileirada — ${run.csv_filename}.`;
    file.value = null;
    patientsFile.value = null;
    patientAnamnesisFile.value = null;
    anamnesisFile.value = null;
    operationsFile.value = null;
    budgetsFile.value = null;
    paymentHeadersFile.value = null;
    paymentItemsFile.value = null;
    dentistMapping.value = {};
    paymentMethodMapping.value = {};
    specialtyMapping.value = {};
    bankAccountId.value = null;
    preview.value = null;
    emit('runCreated', run);
  } catch (err) {
    errorMsg.value = err.message || 'Falha ao enviar planilha.';
  } finally {
    submitting.value = false;
  }
}

function fmtSize(f) {
  return f ? `${f.name} · ${(f.size / 1024).toFixed(1)} KB` : '';
}

const ACTION_LABEL = {
  create: 'Criar',
  update: 'Atualizar',
  skip:   'Pular',
  error:  'Erro',
  // treatment_operations:
  create_session: 'Criar evolução',
  update_session: 'Atualizar evolução',
  create_item:    'Criar item plano',
  update_item:    'Atualizar item plano',
};

// Helpers do passo de mapeamento de dentistas (somente treatment_operations).
function dentistKey(d) {
  // Preferimos o id (estável); se vazio, cai no nome.
  return (d.id && d.id.length > 0) ? d.id : d.name;
}

function setMapping(dentist, value) {
  dentistMapping.value = {
    ...dentistMapping.value,
    [dentistKey(dentist)]: value || undefined,
  };
}

function mappedValueFor(dentist) {
  return dentistMapping.value[dentistKey(dentist)] || '';
}

// PR audit 2026-05-21: auto-mapeia DentistName do CSV → user_id por match
// case+accent-insensitive contra `professionalUsers` da conta. Mesmo critério
// que o `find_user` do ClinicorpAgendaImporter usa no backend (str.strip.
// downcase + tr acentos), pra consistência. Não sobrescreve se a 1ª forma do
// nome já está no índice (idempotente entre múltiplos usuários homônimos).
function normalizeDentistName(s) {
  // NFD separa os acentos do caractere base; a regex remove o range Unicode
  // dos combining diacritical marks (̀-ͯ). Resultado: "André" → "andre".
  return (s || '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '');
}

function setPaymentMethodMapping(kind, value) {
  paymentMethodMapping.value = {
    ...paymentMethodMapping.value,
    [kind]: value || undefined,
  };
}

function setSpecialtyMapping(specialty, value) {
  specialtyMapping.value = {
    ...specialtyMapping.value,
    [specialty]: value || undefined,
  };
}

// Auto-mapeia Specialty → DreCategory.id por match case+acento insensitive
// no `name` da categoria (mesmo critério do auto-map de dentistas). Aliases
// odontológicos comuns garantem matches que diferem só por nomenclatura
// histórica: "Dentística"→"Clínica Geral", "Cirurgia"→"Implantodontia",
// "Clareamento"→"Estética", "Prevenção"→"Periodontia". Sem sobrescrever
// mappings já feitos pelo admin manualmente.
const SPECIALTY_ALIASES = {
  // chave = forma normalizada da Specialty Clinicorp
  // valor = forma normalizada do name da DreCategory esperada
  'dentistica':   'clinica geral',
  'cirurgia':     'implantodontia',
  'clareamento':  'estetica',
  'prevencao':    'periodontia',
  'exame clinico': 'clinica geral',
  'radiologia':   'clinica geral',
  'diagnostico':  'clinica geral',
  'exodontia':    'implantodontia',
  'emergencia':   'clinica geral',
  'hof':          'clinica geral',
};

function autoMapSpecialties() {
  if (!preview.value?.specialties?.items?.length) {
    errorMsg.value = 'Sem especialidades no CSV pra auto-mapear.';
    return;
  }
  const categories = preview.value.specialties.available_categories || [];
  if (!categories.length) {
    errorMsg.value = 'Sem categorias DRE cadastradas. Cadastre em Configurações → Plano de Contas.';
    return;
  }

  // Índice DreCategory.name_normalizado → category
  const categoryByNorm = new Map();
  for (const c of categories) {
    const key = normalizeDentistName(c.name);
    if (key && !categoryByNorm.has(key)) categoryByNorm.set(key, c);
  }

  let matched = 0;
  let aliased = 0;
  let unmatched = 0;
  const newMapping = { ...specialtyMapping.value };

  for (const sp of preview.value.specialties.items) {
    if (newMapping[sp.name]) continue; // não sobrescreve mapping manual

    const norm = normalizeDentistName(sp.name);

    // 1ª tentativa: nome direto
    let cat = categoryByNorm.get(norm);
    if (cat) {
      newMapping[sp.name] = cat.id;
      matched += 1;
      continue;
    }

    // 2ª tentativa: alias odontológico conhecido
    const aliasNorm = SPECIALTY_ALIASES[norm];
    if (aliasNorm) {
      cat = categoryByNorm.get(aliasNorm);
      if (cat) {
        newMapping[sp.name] = cat.id;
        aliased += 1;
        continue;
      }
    }

    unmatched += 1;
  }

  specialtyMapping.value = newMapping;
  errorMsg.value = '';
  const total = preview.value.specialties.items.length;
  successMsg.value =
    `Auto-mapeadas ${matched + aliased}/${total} especialidades` +
    (aliased > 0 ? ` (${matched} match direto + ${aliased} via alias)` : '') +
    (unmatched > 0 ? `. ${unmatched} sem match — selecione manualmente.` : '.');
}

// Formata centavos pra BRL no preview de Specialty (R$ 1.234,56).
function fmtCents(cents) {
  const v = (cents || 0) / 100;
  return v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}

// Label dinâmico da conta bancária no resumo da pré-visualização.
// Antes era hardcoded "1ª conta ativa" mesmo quando o admin escolhia uma
// conta específica — mentia visualmente (importer respeita a escolha, label
// não). Agora resolve o nome real da conta selecionada via active_accounts
// já expostos no payload do previewer (bank_account_payload no Ruby).
const bankAccountLabel = computed(() => {
  const ba = preview.value?.bank_account;
  if (!ba) return '';
  if (ba.strategy === 'create') return '"Importação Clinicorp"';
  if (ba.selected_id) {
    const found = (ba.active_accounts || []).find(a => a.id === ba.selected_id);
    if (found) return `#${found.id} · ${found.name}`;
  }
  return '1ª conta ativa';
});

function autoMapDentists() {
  if (!preview.value?.dentists?.length || !professionalUsers.value.length) {
    errorMsg.value = 'Sem dentistas no CSV ou lista de usuários vazia.';
    return;
  }

  // Índice nome_normalizado → user (1ª aparição vence em caso de homônimo)
  const userByNorm = new Map();
  for (const u of professionalUsers.value) {
    const key = normalizeDentistName(u.name);
    if (key && !userByNorm.has(key)) userByNorm.set(key, u);
  }

  let matched = 0;
  let unmatched = 0;
  const newMapping = { ...dentistMapping.value };

  for (const d of preview.value.dentists) {
    const norm = normalizeDentistName(d.name);
    const user = userByNorm.get(norm);
    if (user) {
      newMapping[dentistKey(d)] = user.id;
      matched += 1;
    } else {
      unmatched += 1;
    }
  }

  dentistMapping.value = newMapping;
  errorMsg.value = '';
  successMsg.value = `Auto-mapeados ${matched}/${preview.value.dentists.length} dentistas por nome.${unmatched ? ` ${unmatched} sem match — selecione manualmente.` : ''}`;
}
</script>

<template>
  <div class="mig-card">
    <h2 style="font-size: 16px; font-weight: 700; margin: 0 0 16px;">Nova migração</h2>

    <div class="mig-grid">
      <div>
        <label class="mig-label">Conta de destino</label>
        <select v-model="accountId" class="mig-select">
          <option :value="null">Selecione a conta…</option>
          <option v-for="a in accounts" :key="a.id" :value="a.id">
            #{{ a.id }} — {{ a.name }}
          </option>
        </select>
        <div class="mig-help">A planilha será importada para a conta selecionada (account_id).</div>
      </div>

      <div>
        <label class="mig-label">Tipo de migração</label>
        <select v-model="kind" class="mig-select">
          <option v-for="k in KINDS" :key="k.value" :value="k.value" :disabled="k.disabled">
            {{ k.label }}
          </option>
        </select>
        <div class="mig-help">Em "Pacientes" você pode anexar também os 2 CSVs de anamnese.</div>
      </div>

      <div>
        <label class="mig-label">Origem</label>
        <select v-model="source" class="mig-select">
          <option v-for="s in SOURCES" :key="s.value" :value="s.value" :disabled="s.disabled">
            {{ s.label }}
          </option>
        </select>
        <div class="mig-help">Define o parser do CSV (mapeamento de colunas).</div>
      </div>

      <!-- Multi-file: Patients flow -->
      <template v-if="isPatients">
        <div>
          <label class="mig-label">Patient.csv ou .xlsx (obrigatório)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">📄</div>
            <div class="mig-drop__text">
              {{ converting ? 'Convertendo planilha…' : patientsFile ? fmtSize(patientsFile) : 'Selecione Patient.csv ou .xlsx' }}
            </div>
            <input type="file" accept=".csv,.xlsx,.xls,.xlsm,.xlsb,.ods,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel" style="display: none;" :disabled="converting" @change="(e) => pickFile(e, 'patients')" />
          </label>
        </div>
        <div>
          <label class="mig-label">PatientAnamnesis.csv ou .xlsx (opcional)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">🧾</div>
            <div class="mig-drop__text">
              {{ converting ? 'Convertendo planilha…' : patientAnamnesisFile ? fmtSize(patientAnamnesisFile) : 'Selecione PatientAnamnesis' }}
            </div>
            <input type="file" accept=".csv,.xlsx,.xls,.xlsm,.xlsb,.ods,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel" style="display: none;" :disabled="converting" @change="(e) => pickFile(e, 'patientAnamnesis')" />
          </label>
        </div>
        <div>
          <label class="mig-label">Anamnesis.csv ou .xlsx (opcional)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">📋</div>
            <div class="mig-drop__text">
              {{ converting ? 'Convertendo planilha…' : anamnesisFile ? fmtSize(anamnesisFile) : 'Selecione Anamnesis' }}
            </div>
            <input type="file" accept=".csv,.xlsx,.xls,.xlsm,.xlsb,.ods,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel" style="display: none;" :disabled="converting" @change="(e) => pickFile(e, 'anamnesis')" />
          </label>
        </div>
      </template>

      <!-- treatment_operations flow: 1 arquivo + passo de mapeamento -->
      <template v-else-if="isOperations">
        <div>
          <label class="mig-label">TreatmentOperation.csv ou .xlsx (obrigatório)</label>
          <label class="mig-drop">
            <div class="mig-drop__icon">🦷</div>
            <div class="mig-drop__text">
              {{ converting ? 'Convertendo planilha…' : operationsFile ? fmtSize(operationsFile) : 'Selecione TreatmentOperation.csv ou .xlsx' }}
            </div>
            <div class="mig-drop__hint">
              Procedimentos executados viram entradas na aba Evolução; planejados viram itens em "Histórico Clinicorp" no Plano de Tratamento.
            </div>
            <input type="file" accept=".csv,.xlsx,.xls,.xlsm,.xlsb,.ods,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel" style="display: none;" :disabled="converting" @change="(e) => pickFile(e, 'operations')" />
          </label>
        </div>
      </template>

      <!-- financial flow (F-10): 3 arquivos + mapeamento de dentistas + estratégia de conta -->
      <template v-else-if="isFinancial">
        <div>
          <label class="mig-label">Budgets.csv ou .xlsx (obrigatório)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">📋</div>
            <div class="mig-drop__text">
              {{ converting ? 'Convertendo planilha…' : budgetsFile ? fmtSize(budgetsFile) : 'Selecione Budgets' }}
            </div>
            <input type="file" accept=".csv,.xlsx,.xls,.xlsm,.xlsb,.ods,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel" style="display: none;" :disabled="converting" @change="(e) => pickFile(e, 'budgets')" />
          </label>
        </div>
        <div>
          <label class="mig-label">PaymentHeader.csv ou .xlsx (obrigatório)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">🧾</div>
            <div class="mig-drop__text">
              {{ converting ? 'Convertendo planilha…' : paymentHeadersFile ? fmtSize(paymentHeadersFile) : 'Selecione PaymentHeader' }}
            </div>
            <input type="file" accept=".csv,.xlsx,.xls,.xlsm,.xlsb,.ods,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel" style="display: none;" :disabled="converting" @change="(e) => pickFile(e, 'paymentHeaders')" />
          </label>
        </div>
        <div>
          <label class="mig-label">PaymentItem.csv ou .xlsx (obrigatório)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">💰</div>
            <div class="mig-drop__text">
              {{ converting ? 'Convertendo planilha…' : paymentItemsFile ? fmtSize(paymentItemsFile) : 'Selecione PaymentItem' }}
            </div>
            <input type="file" accept=".csv,.xlsx,.xls,.xlsm,.xlsb,.ods,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel" style="display: none;" :disabled="converting" @change="(e) => pickFile(e, 'paymentItems')" />
          </label>
        </div>
        <div>
          <label class="mig-label">Conta bancária para recebimentos</label>
          <select v-model="bankAccountStrategy" class="mig-select" @change="bankAccountId = null">
            <option value="create">Criar conta dedicada "Importação Clinicorp"</option>
            <option value="existing">Usar conta bancária já cadastrada</option>
          </select>
          <select
            v-if="bankAccountStrategy === 'existing' && financialSettings.bank_accounts.length"
            v-model="bankAccountId"
            class="mig-select"
            style="margin-top: 8px;"
          >
            <option :value="null">— 1ª conta ativa (auto) —</option>
            <option v-for="ba in financialSettings.bank_accounts" :key="ba.id" :value="ba.id">
              #{{ ba.id }} · {{ ba.name }}{{ ba.kind ? ` (${ba.kind})` : '' }}
            </option>
          </select>
          <div class="mig-help">
            <span v-if="bankAccountStrategy === 'create'">Cria/usa uma conta tipo Corrente chamada "Importação Clinicorp" — fácil filtrar depois.</span>
            <span v-else-if="bankAccountId">Recebimentos vão pra conta #{{ bankAccountId }} escolhida.</span>
            <span v-else>Usa a 1ª conta ativa da clínica. Se não houver conta cadastrada, a importação aborta com erro.</span>
          </div>
        </div>
      </template>

      <!-- Single-file: legacy flow (agenda, etc) -->
      <div v-else>
        <label class="mig-label">Arquivo CSV ou XLSX</label>
        <label class="mig-drop">
          <div class="mig-drop__icon">📄</div>
          <div class="mig-drop__text">
            {{ converting ? 'Convertendo planilha…' : file ? fmtSize(file) : 'Clique para selecionar o arquivo (CSV ou XLSX)' }}
          </div>
          <div class="mig-drop__hint">Suporta até 25MB · ~10.000 linhas · XLSX é convertido pra CSV no navegador</div>
          <input type="file" accept=".csv,.xlsx,.xls,.xlsm,.xlsb,.ods,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel" style="display: none;" :disabled="converting" @change="(e) => pickFile(e, 'file')" />
        </label>
      </div>
    </div>

    <div v-if="errorMsg" class="mig-error">{{ errorMsg }}</div>
    <div v-if="successMsg" class="mig-success">{{ successMsg }}</div>

    <div v-if="preview" class="mig-preview">
      <h3 style="font-size: 13px; font-weight: 700; margin: 16px 0 8px; color: #374151;">
        Pré-visualização — nada foi gravado ainda
      </h3>
      <div v-if="!isOperations" class="mig-preview__summary">
        <span class="mig-preview__chip">Total: {{ preview.summary.total }}</span>
        <template v-if="isFinancial">
          <span class="mig-preview__chip">Orçamentos: {{ preview.summary.budgets_total }}</span>
          <span class="mig-preview__chip">Cobranças: {{ preview.summary.headers_total }}</span>
          <span class="mig-preview__chip">Parcelas: {{ preview.summary.items_total }}</span>
        </template>
        <span class="mig-preview__chip mig-preview__chip--create">Criar: {{ preview.summary.would_create }}</span>
        <span class="mig-preview__chip mig-preview__chip--update">Atualizar: {{ preview.summary.would_update }}</span>
        <span class="mig-preview__chip mig-preview__chip--skip">Pular: {{ preview.summary.would_skip }}</span>
        <span v-if="preview.summary.warnings" class="mig-preview__chip mig-preview__chip--warn">
          Avisos: {{ preview.summary.warnings }}
        </span>
        <span v-if="preview.summary.errors" class="mig-preview__chip mig-preview__chip--err">
          Linhas inválidas: {{ preview.summary.errors }}
        </span>
      </div>

      <!-- Conciliação financeira (canon §4) — só no fluxo financial -->
      <div v-if="isFinancial && preview.reconciliation" class="mig-preview__reconciliation">
        <h4 style="font-size: 12px; font-weight: 700; margin: 12px 0 6px; color: #374151;">
          Conciliação esperada (canon §4)
        </h4>
        <div class="mig-preview__summary">
          <span class="mig-preview__chip">Total a receber: {{ preview.reconciliation.total_launched_brl }}</span>
          <span class="mig-preview__chip mig-preview__chip--create">Recebido: {{ preview.reconciliation.total_received_brl }}</span>
          <span class="mig-preview__chip mig-preview__chip--warn">Pendente: {{ preview.reconciliation.balance_to_receive_brl }}</span>
        </div>
        <div class="mig-help" style="margin-top: 4px;">
          {{ preview.reconciliation.items_received }} recebidas ·
          {{ preview.reconciliation.items_pending }} pendentes ·
          {{ preview.reconciliation.items_overdue }} vencidas ·
          {{ preview.reconciliation.items_canceled }} canceladas ·
          {{ preview.reconciliation.partial_headers_for_review }} cabeçalhos parciais (revisar manualmente)
        </div>
        <div v-if="preview.bank_account" class="mig-help" style="margin-top: 4px;">
          Conta bancária: <strong>{{ bankAccountLabel }}</strong>
          <span v-if="preview.bank_account.will_create_dedicated"> (será criada agora)</span>
          <span v-else-if="preview.bank_account.strategy === 'existing' && !preview.bank_account.has_active_accounts" style="color: #b91c1c;">
            — ATENÇÃO: clínica não tem conta ativa cadastrada. Importação vai abortar.
          </span>
        </div>

        <!-- Aviso de PeriodClosure: linhas que caem em mês contábil fechado
             serão ignoradas (skipadas) pelo importer. Admin pode reabrir o
             período em Settings → Contador e re-importar pra incluí-las. -->
        <div
          v-if="preview.period_closure && preview.period_closure.blocked_rows > 0"
          class="mig-error-list__item mig-error-list__item--warning"
          style="margin-top: 8px;"
        >
          <strong>⚠ {{ preview.period_closure.blocked_rows }} parcela(s) em período contábil fechado</strong>
          — serão IGNORADAS na importação. Reabra o período em
          <em>Settings → Financeiro → Contador</em> antes de iniciar pra incluí-las.
        </div>
      </div>

      <!-- Mapeamento "kind Clinicorp → PaymentMethod Klivy" (canon Settings).
           Admin escolhe um PaymentMethod cadastrado pra cada kind encontrado
           nos CSVs. Kinds sem mapping caem no fallback do importer (auto-cria
           "Importação Clinicorp · X"). Recomenda cadastrar antes em
           Settings → Formas de Pagamento → vincular Cielo/Stone/etc. -->
      <div v-if="isFinancial && preview.payment_kinds && preview.payment_kinds.kinds.length" class="mig-dentist-map">
        <h4 style="font-size: 13px; font-weight: 700; margin: 16px 0 6px;">
          Mapear formas de pagamento ({{ preview.payment_kinds.kinds.length }} tipos)
        </h4>
        <div class="mig-help" style="margin-bottom: 8px;">
          Pra cada tipo encontrado nos CSVs, escolha o <strong>PaymentMethod</strong> já
          cadastrado em Settings → Formas de Pagamento da clínica destino
          (ex: <em>"PIX Cielo"</em>, <em>"Crédito Stone"</em>). Deixar vazio = importer
          auto-cria <code>"Importação Clinicorp · X"</code> como fallback (pode
          renomear/reatribuir depois sem perder vínculo).
        </div>
        <div class="mig-dentist-map__list">
          <div v-for="pk in preview.payment_kinds.kinds" :key="pk.kind" class="mig-dentist-map__row">
            <div class="mig-dentist-map__name">
              <strong>{{ pk.label }}</strong>
              <span style="color: #6b7280; font-weight: 400;">
                · {{ pk.count }} parcela{{ pk.count !== 1 ? 's' : '' }}
                <span style="font-size: 11px;"> · kind <code>{{ pk.kind }}</code></span>
              </span>
            </div>
            <select
              :value="paymentMethodMapping[pk.kind] || ''"
              class="mig-select"
              style="max-width: 360px;"
              @change="(e) => setPaymentMethodMapping(pk.kind, e.target.value)"
            >
              <option value="">— Auto-criar "Importação Clinicorp · {{ pk.label }}" —</option>
              <option v-for="pm in pk.available_methods" :key="pm.id" :value="pm.id">
                #{{ pm.id }} · {{ pm.name }}{{ pm.provider ? ` (${pm.provider})` : '' }}
              </option>
            </select>
          </div>
        </div>
        <div v-if="loadingFinancial" class="mig-help">Carregando formas de pagamento…</div>
      </div>

      <!-- Mapeamento "Specialty Clinicorp → DreCategory Klivy" (canon DRE).
           Clinicorp não exporta categoria DRE — só `Specialty` ("Cirurgia",
           "Dentística", etc.). Admin pode mapear cada especialidade pra uma
           categoria do Plano de Contas, e o importer preenche
           `financial_dre_category_id` em Installments + Entries.
           Sem mapping = nil → operador reclassifica em Settings → Reclassificar. -->
      <div v-if="isFinancial && preview.specialties && preview.specialties.items.length" class="mig-dentist-map">
        <h4 style="font-size: 13px; font-weight: 700; margin: 16px 0 6px; display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap;">
          <span>Mapear especialidades → categorias DRE ({{ preview.specialties.items.length }} tipos)</span>
          <button
            type="button"
            class="mig-btn mig-btn--ghost"
            style="font-size: 12px; font-weight: 600; padding: 6px 12px;"
            :disabled="!preview.specialties.available_categories.length"
            @click="autoMapSpecialties"
          >
            Auto-mapear por nome
          </button>
        </h4>
        <div class="mig-help" style="margin-bottom: 8px;">
          Cada Budget Clinicorp tem uma <strong>Specialty</strong> dominante
          (ex: <em>"Cirurgia"</em>, <em>"Dentística"</em>). Escolha a
          categoria <strong>DRE</strong> equivalente pra cada uma — o importer
          vai gravar <code>financial_dre_category_id</code> nas Installments
          e Entries criadas, e DRE/Dashboard refletem direto.
          Deixar vazio = sem categoria (operador reclassifica depois em
          <em>Settings → Reclassificar</em>).
        </div>
        <div class="mig-dentist-map__list">
          <div v-for="sp in preview.specialties.items" :key="sp.name" class="mig-dentist-map__row">
            <div class="mig-dentist-map__name">
              <strong>{{ sp.name }}</strong>
              <span style="color: #6b7280; font-weight: 400;">
                · {{ sp.count }} orçamento{{ sp.count !== 1 ? 's' : '' }}
                <span style="font-size: 11px;"> · {{ fmtCents(sp.value_cents) }}</span>
              </span>
            </div>
            <select
              :value="specialtyMapping[sp.name] || ''"
              class="mig-select"
              style="max-width: 360px;"
              @change="(e) => setSpecialtyMapping(sp.name, e.target.value)"
            >
              <option value="">— Sem categoria (reclassificar depois) —</option>
              <option v-for="dre in preview.specialties.available_categories" :key="dre.id" :value="dre.id">
                #{{ dre.id }} · {{ dre.name }}
              </option>
            </select>
          </div>
        </div>
      </div>

      <!-- Resumo específico de TreatmentOperation: 4 contadores diferentes em
           vez de 3 (sessions vs items). -->
      <div v-else class="mig-preview__summary">
        <span class="mig-preview__chip">Total: {{ preview.summary.total }}</span>
        <span class="mig-preview__chip mig-preview__chip--create">
          Evoluções novas: {{ preview.summary.would_create_session }}
        </span>
        <span class="mig-preview__chip mig-preview__chip--update">
          Evoluções atualizadas: {{ preview.summary.would_update_session }}
        </span>
        <span class="mig-preview__chip mig-preview__chip--create">
          Itens plano novos: {{ preview.summary.would_create_item }}
        </span>
        <span class="mig-preview__chip mig-preview__chip--update">
          Itens plano atualizados: {{ preview.summary.would_update_item }}
        </span>
        <span class="mig-preview__chip mig-preview__chip--skip">Pular: {{ preview.summary.would_skip }}</span>
        <span v-if="preview.summary.warnings" class="mig-preview__chip mig-preview__chip--warn">
          Avisos: {{ preview.summary.warnings }}
        </span>
      </div>

      <div v-if="preview.anamneses" class="mig-help" style="margin-bottom: 8px;">
        Anamneses: {{ preview.anamneses.total }} no CSV ·
        {{ preview.anamneses.linked }} serão vinculadas ·
        {{ preview.anamneses.unlinked }} sem vínculo (ID truncado pelo Excel).
      </div>

      <!-- Passo de mapeamento de dentistas (treatment_operations + financial) -->
      <div v-if="(isOperations || isFinancial) && preview.dentists && preview.dentists.length" class="mig-dentist-map">
        <h4 style="font-size: 13px; font-weight: 700; margin: 16px 0 6px; display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap;">
          <span>Mapear dentistas → usuários ({{ preview.dentists.length }} distintos)</span>
          <button
            type="button"
            class="mig-btn mig-btn--ghost"
            style="font-size: 12px; font-weight: 600; padding: 6px 12px;"
            :disabled="loadingUsers || !professionalUsers.length"
            @click="autoMapDentists"
          >
            Auto-mapear por nome
          </button>
        </h4>
        <div class="mig-help" style="margin-bottom: 8px;">
          A planilha tem nomes do Clinicorp. Escolha o usuário Klivy correspondente,
          ou "Ignorar" pra deixar o {{ isFinancial ? 'orçamento' : 'procedimento' }} sem profissional vinculado.
          Use <strong>Auto-mapear por nome</strong> pra preencher de uma vez (case+acento insensitive),
          ajuste o que não casou, e clique em <strong>Regerar pré-visualização</strong> pra ver o efeito.
        </div>
        <div class="mig-dentist-map__list">
          <div v-for="d in preview.dentists" :key="dentistKey(d)" class="mig-dentist-map__row">
            <div class="mig-dentist-map__name">
              <strong>{{ d.name || '(sem nome)' }}</strong>
              <span style="color: #6b7280; font-weight: 400;">
                · {{ d.count }} procedimento{{ d.count !== 1 ? 's' : '' }}
                <span v-if="d.id" style="font-size: 11px;"> · id {{ d.id }}</span>
              </span>
            </div>
            <select
              :value="mappedValueFor(d)"
              class="mig-select"
              style="max-width: 320px;"
              @change="(e) => setMapping(d, e.target.value)"
            >
              <option value="">— Selecione um usuário —</option>
              <option value="ignore">Ignorar (sem profissional)</option>
              <option v-for="u in professionalUsers" :key="u.id" :value="u.id">
                {{ u.name }}{{ u.klivy_role ? ` · ${u.klivy_role}` : '' }}
              </option>
            </select>
          </div>
        </div>
        <div v-if="loadingUsers" class="mig-help">Carregando lista de usuários…</div>
      </div>

      <!-- Linhas: layout original p/ patients; layout específico p/ operations; financial -->
      <div v-if="isPatients" class="mig-preview__rows">
        <div v-for="(row, idx) in preview.rows" :key="idx" class="mig-preview__row">
          <span :class="['mig-preview__action', `mig-preview__action--${row.action}`]">
            {{ ACTION_LABEL[row.action] || row.action }}
          </span>
          <div>
            <div class="mig-preview__row-name">
              {{ row.name || '(sem nome)' }}
              <span v-if="row.cpf" style="color:#6b7280; font-weight:400;"> · CPF {{ row.cpf }}</span>
            </div>
            <div class="mig-preview__row-meta">
              Linha {{ row.line }}
              <span v-if="row.fields.email"> · {{ row.fields.email }}</span>
              <span v-if="row.fields.phone"> · {{ row.fields.phone }}</span>
              <span v-if="row.fields.city"> · {{ row.fields.city }}</span>
              <span v-if="row.fields.insurance_plan"> · plano: {{ row.fields.insurance_plan }}</span>
            </div>
            <div v-if="row.fields.notes_preview" class="mig-preview__row-meta">
              📝 {{ row.fields.notes_preview }}
            </div>
            <div v-if="row.reason" class="mig-preview__row-reason">{{ row.reason }}</div>
          </div>
        </div>
      </div>

      <div v-else-if="isFinancial" class="mig-preview__rows">
        <div v-for="(row, idx) in preview.rows" :key="idx" class="mig-preview__row">
          <span :class="['mig-preview__action', `mig-preview__action--${row.action}`]">
            {{ ACTION_LABEL[row.action] || row.action }}
          </span>
          <div>
            <div class="mig-preview__row-name">
              <span style="color:#6b7280; font-weight:400; text-transform: uppercase; font-size: 10px;">{{ row.kind }}</span>
              · {{ row.label }}
            </div>
            <div class="mig-preview__row-meta">
              <span v-if="row.patient_name">{{ row.patient_name }}</span>
              <span v-if="row.type"> · {{ row.type }}</span>
              <span v-if="row.received"> · recebido</span>
              <span v-else-if="row.canceled"> · cancelado</span>
            </div>
            <div v-if="row.reason" class="mig-preview__row-reason">{{ row.reason }}</div>
          </div>
        </div>
      </div>

      <div v-else class="mig-preview__rows">
        <div v-for="(row, idx) in preview.rows" :key="idx" class="mig-preview__row">
          <span :class="['mig-preview__action', `mig-preview__action--${row.action}`]">
            {{ ACTION_LABEL[row.action] || row.action }}
          </span>
          <div>
            <div class="mig-preview__row-name">
              {{ row.procedure || '(sem procedimento)' }}
              <span v-if="row.condition" style="color:#6b7280; font-weight:400;"> · {{ row.condition }}</span>
            </div>
            <div class="mig-preview__row-meta">
              Linha {{ row.line }} · paciente: {{ row.patient_name || '—' }}
              <span v-if="row.dentist"> · dentista: {{ row.dentist }}</span>
              <span v-if="row.executed === true"> · executado</span>
              <span v-else-if="row.executed === false"> · planejado</span>
              <span v-if="row.performed_at"> · {{ row.performed_at.substring(0, 10) }}</span>
            </div>
            <div v-if="row.reason" class="mig-preview__row-reason">{{ row.reason }}</div>
          </div>
        </div>
      </div>

      <div v-if="preview.warnings && preview.warnings.length" style="margin-top: 12px;">
        <h4 style="font-size: 12px; font-weight: 600; margin: 0 0 6px; color: #78350f;">
          Avisos ({{ preview.warnings.length }})
        </h4>
        <div class="mig-error-list">
          <div v-for="(w, idx) in preview.warnings" :key="idx" class="mig-error-list__item mig-error-list__item--warning">
            <strong>Linha {{ w.line }}:</strong> {{ w.message }}
          </div>
        </div>
      </div>
    </div>

    <div class="mig-actions">
      <button v-if="isPatients || isOperations || isFinancial" class="mig-btn mig-btn--ghost" :disabled="!canPreview" @click="runPreview">
        {{ previewing ? 'Analisando…' : (preview ? 'Regerar pré-visualização' : 'Pré-visualizar') }}
      </button>
      <button class="mig-btn mig-btn--primary" :disabled="!canSubmit" @click="submit">
        {{ submitting ? 'Enviando…' : (preview ? 'Confirmar e iniciar' : 'Iniciar migração') }}
      </button>
    </div>
  </div>
</template>
