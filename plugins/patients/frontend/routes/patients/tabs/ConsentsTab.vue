<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * ConsentsTab — Aba "Consentimentos e Assinaturas" do prontuário.
 *
 * Gestão jurídica de termos: LGPD, autorização de imagem, procedimentos
 * estéticos (botox, filler, fototerapia, peeling), procedimento cirúrgico,
 * anestesia, menor de idade, geral. Suporta criação, assinatura presencial
 * (canvas digital), envio remoto via WhatsApp, e revogação.
 *
 * Recebe `patient` como prop para substituir [NOME], [CPF], [RG], [ENDEREÇO]
 * etc nos templates. Auto-suficiente: lê patientId da rota.
 *
 * Componente extraído de Record.vue (Fase 5 do refactor).
 */
import { ref, computed, nextTick, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import ConsentsAPI from '@plugins/patients/frontend/api/patients/consents';

const props = defineProps({
  patient: { type: Object, required: true },
});

const route = useRoute();

const BRT = 'America/Sao_Paulo';

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return formatDateBR(dateStr) || '—';
};

// ── State ──────────────────────────────────────────────────
const consents = ref([]);
const consentLoading = ref(false);
const showConsentModal = ref(false);
const showSignModal = ref(false);
const showViewModal = ref(false);
const consentInView = ref(null);
const signingConsentId = ref(null);
const consentModalLoading = ref(false);
const signatureCanvas = ref(null);
const isDrawing = ref(false);
const hasSignature = ref(false);

const CONSENT_TYPES = [
  {
    value: 'lgpd',
    label: 'Termo LGPD / Privacidade de Dados',
    icon: 'i-lucide-shield-check',
    color: 'blue',
    description:
      'Autorização para coleta, uso e armazenamento de dados pessoais conforme LGPD (Lei 13.709/2018).',
    template:
      'TERMO DE CONSENTIMENTO PARA USO DE DADOS PESSOAIS (LGPD)\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], declaro que fui devidamente informado(a) sobre:\n\n1. DADOS COLETADOS: nome, data de nascimento, CPF, endereço, contatos, histórico de saúde, fotos e registros de atendimento.\n2. FINALIDADE: gestão do prontuário, agendamento, comunicação sobre tratamentos e emissão de documentos.\n3. ARMAZENAMENTO: servidores com criptografia e acesso restrito.\n4. COMPARTILHAMENTO: não ocorre sem autorização prévia, salvo exigência legal.\n5. DIREITOS: acesso, correção, exclusão ou revogação a qualquer momento.\n\nConsinto expressamente com o tratamento dos meus dados pessoais.',
  },
  {
    value: 'autorizacao_imagem',
    label: 'Autorização de Uso de Imagem',
    icon: 'i-lucide-camera',
    color: 'purple',
    description:
      'Autorização para captura e uso de fotos e vídeos para documentação clínica.',
    template:
      'AUTORIZAÇÃO DE USO DE IMAGEM\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], AUTORIZO a clínica a fotografar e/ou filmar minha imagem durante e após procedimentos estéticos para fins de documentação clínica e acompanhamento de resultados.\n\nDeclaro ciência de que as imagens são armazenadas com segurança e acesso restrito ao corpo clínico.',
  },
  {
    value: 'botox',
    label: 'Consentimento - Toxina Botulínica (Botox)',
    icon: 'i-lucide-syringe',
    color: 'emerald',
    description:
      'Termo de consentimento informado para aplicação de toxina botulínica.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - TOXINA BOTULÍNICA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], declaro ter sido informado(a) sobre:\n\n1. Aplicação de toxina botulínica tipo A em músculos-alvo para relaxamento temporário.\n2. Efeito esperado: início em 3-7 dias; duração de 3-6 meses.\n3. Riscos: hematoma, ptose palpebral, assimetria, cefaleia, reação alérgica (rara).\n4. Contraindicações: gestantes, lactantes, miastenia gravis.\n5. Sem garantia de resultado (obrigação de meios).\n\nDeclaro compreensão plena e consinto com o procedimento.',
  },
  {
    value: 'preenchimento',
    label: 'Consentimento - Preenchimento Dérmico (Filler)',
    icon: 'i-lucide-droplet',
    color: 'cyan',
    description:
      'Termo de consentimento para aplicação de preenchedores dérmicos.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - PREENCHIMENTO DÉRMICO\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de PREENCHIMENTO DÉRMICO com ácido hialurônico.\n\n1. Riscos: edema, equimose, assimetria, nódulos, migração, oclusão vascular (rara mas grave), cegueira (extremamente raro).\n2. Duração: 6 meses a 2 anos conforme produto e área.\n3. Contraindicações: gestação, lactação, doenças autoimunes ativas.\n4. Sem garantia de resultado.\n\nDeclaro ter entendido os riscos e alternativas ao tratamento.',
  },
  {
    value: 'fototerapia',
    label: 'Consentimento - Laser / Fototerapia / LED',
    icon: 'i-lucide-zap',
    color: 'amber',
    description:
      'Termo para procedimentos com laser, luz pulsada, LED ou radiofrequência.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - LASER / FOTOTERAPIA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de LASER / LUZ PULSADA / LED / RADIOFREQUÊNCIA.\n\n1. Riscos: eritema, edema, hiperpigmentação pós-inflamatória, hipopigmentação, queimaduras (raros).\n2. Cuidados: protetor solar FPS 60+ por 30 dias; evitar sol direto.\n3. Contraindicações: bronzeamento recente, gestação, fotossensibilizantes.\n\nDeclaro ciência dos riscos e autorizo o procedimento.',
  },
  {
    value: 'peeling',
    label: 'Consentimento - Peeling Químico / Dermabrasão',
    icon: 'i-lucide-layers',
    color: 'rose',
    description: 'Termo para peelings químicos de diferentes profundidades.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - PEELING QUÍMICO\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de PEELING QUÍMICO.\n\n1. Riscos: eritema prolongado, descamação, hiperpigmentação, herpes recorrente, cicatrizes (raros).\n2. Cuidados: fotoproteção rigorosa por 60 dias; evitar maquiagem por 7 dias.\n3. Contraindicações: gestação, lactação, herpes ativo, isotretinoína nos últimos 6 meses.\n\nDeclaro compreensão e concordo com o procedimento.',
  },
  {
    value: 'menor_idade',
    label: 'Autorização - Paciente Menor de Idade',
    icon: 'i-lucide-baby',
    color: 'orange',
    description:
      'Autorização do responsável legal para tratamento de menor de 18 anos.',
    template:
      'AUTORIZAÇÃO PARA TRATAMENTO DE MENOR DE IDADE\n\nEu, [NOME DO RESPONSÁVEL], portador(a) do CPF [CPF], responsável legal de [NOME DO PACIENTE], AUTORIZO os procedimentos indicados.\n\n1. Tenho ciência plena dos procedimentos e seus riscos.\n2. Fui informado(a) sobre benefícios e alternativas.\n3. Autorizo uso de imagens apenas para documentação clínica.\n\nEm conformidade com ECA (Lei 8.069/90) e normativas do CFM/CFF.',
  },
  {
    value: 'procedimento_cirurgico',
    label: 'Consentimento - Procedimento Cirúrgico Minor',
    icon: 'i-lucide-activity',
    color: 'red',
    description:
      'Termo para pequenas cirurgias ambulatoriais (biópsia, exérese, etc.).',
    template:
      'TERMO DE CONSENTIMENTO - PROCEDIMENTO CIRÚRGICO MENOR\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com o procedimento cirúrgiico indicado.\n\n1. Fui informado sobre o tipo de procedimento, anestesia local e riscos de sangramento, infecção e cicatriz.\n2. Compreendo os cuidados pós-operatórios necessários.\n3. Aceito os riscos inerentes ao procedimento proposto.',
  },
  {
    value: 'anestesia',
    label: 'Consentimento - Anestesia Local/Tópica',
    icon: 'i-lucide-pill',
    color: 'violet',
    description:
      'Consentimento específico para uso de anestesia local ou tópica.',
    template:
      'TERMO DE CONSENTIMENTO - ANESTESIA LOCAL/TÓPICA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], fui informado(a) sobre o uso de anestesia local ou tópica.\n\n1. Reações possíveis: ardência, eritema, edema, tonturas, reações alérgicas (raras).\n2. Alergias conhecidas: [ ] NÃO POSSUO / [ ] POSSUO: ___________\n3. Medicamentos em uso: ___________\n\nConsinto com o uso da anestesia necessária para o procedimento indicado.',
  },
  {
    value: 'geral',
    label: 'Termo de Consentimento Geral',
    icon: 'i-lucide-file-check',
    color: 'slate',
    description:
      'Termo geral para procedimentos não cobertos pelos tipos específicos acima.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO GERAL\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], concordo com a realização do procedimento/tratamento indicado.\n\n1. Fui informado(a) sobre objetivos, riscos, benefícios e alternativas.\n2. Tive oportunidade de esclarecer todas as minhas dúvidas.\n3. Compreendo que resultados não são garantidos.\n4. Poderei revogar este consentimento a qualquer momento antes do procedimento.\n\nElaborado conforme resoluções do CFM e normas da ANVISA.',
  },
];

const CONSENT_STATUS_CONFIG = {
  pendente: { label: 'Pendente', cls: 'bg-amber-500/10 text-amber-400 border-amber-500/20', icon: 'i-lucide-clock' },
  assinado_localmente: { label: 'Assinado', cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20', icon: 'i-lucide-check-circle' },
  assinado_remotamente: { label: 'Assinado (Remoto)', cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20', icon: 'i-lucide-check-circle' },
  signed: { label: 'Assinado', cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20', icon: 'i-lucide-check-circle' },
  vencido: { label: 'Vencido', cls: 'bg-red-500/10 text-red-400 border-red-500/20', icon: 'i-lucide-alert-triangle' },
  revogado: { label: 'Revogado', cls: 'bg-slate-500/10 text-slate-400 border-slate-500/20', icon: 'i-lucide-x-circle' },
};

const newConsentForm = ref({
  consent_type: '',
  title: '',
  body: '',
  expires_in_months: 12,
  observations: '',
});

const fetchConsents = async () => {
  consentLoading.value = true;
  try {
    const res = await ConsentsAPI.get(route.params.patientId);
    consents.value = res.data?.data || res.data || [];
  } catch (error) {
    // ignore
  } finally {
    consentLoading.value = false;
  }
};

const consentTypeDetail = computed(() =>
  CONSENT_TYPES.find(t => t.value === newConsentForm.value.consent_type)
);

const selectConsentType = type => {
  if (!type) return;
  newConsentForm.value.consent_type = type.value;
  newConsentForm.value.title = type.label;

  // Formata data de nascimento para DD/MM/AAAA
  let birthFormatted = '________________';
  if (props.patient?.birthdate) {
    try {
      const d = new Date(props.patient.birthdate);
      birthFormatted = d.toLocaleDateString('pt-BR', { timeZone: BRT });
    } catch {
      birthFormatted = props.patient.birthdate;
    }
  }

  let cpfFormatted = '________________';
  if (props.patient?.cpf) {
    cpfFormatted = props.patient.cpf.replace(
      /(\d{3})(\d{3})(\d{3})(\d{2})/,
      '$1.$2.$3-$4'
    );
  }

  const addr = props.patient?.address || {};
  const fullAddress =
    [
      addr.street, addr.number, addr.complement, addr.neighborhood,
      addr.city, addr.state, addr.zip,
    ]
      .filter(Boolean)
      .join(', ') || '________________';

  newConsentForm.value.body = type.template
    .replace('[NOME DO PACIENTE]', props.patient?.name || '________________')
    .replace('[NOME DO RESPONSÁVEL]', '________________')
    .replace('[CPF]', cpfFormatted)
    .replace('[DATA DE NASCIMENTO]', birthFormatted)
    .replace('[ENDEREÇO]', fullAddress)
    .replace('[RG]', props.patient?.rg || '________________')
    .replace('[EMAIL]', props.patient?.email || '________________')
    .replace('[TELEFONE]', props.patient?.phone || '________________');
};

const onConsentTypeChange = () => {
  const type = CONSENT_TYPES.find(t => t.value === newConsentForm.value.consent_type);
  selectConsentType(type);
};

const openConsentModal = () => {
  newConsentForm.value = {
    consent_type: '',
    title: '',
    body: '',
    expires_in_months: 12,
    observations: '',
  };
  showConsentModal.value = true;
};

const createConsent = async () => {
  if (!newConsentForm.value.consent_type || !newConsentForm.value.title) {
    useAlert('Selecione o tipo de consentimento.');
    return;
  }
  consentModalLoading.value = true;
  try {
    await ConsentsAPI.create(route.params.patientId, {
      title: newConsentForm.value.title,
      document_type: newConsentForm.value.consent_type,
      body: newConsentForm.value.body,
      expires_after_days: newConsentForm.value.expires_in_months * 30,
      observations: newConsentForm.value.observations,
    });
    showConsentModal.value = false;
    await fetchConsents();
    useAlert('Consentimento criado com sucesso!');
  } catch (err) {
    useAlert(`Erro ao criar consentimento: ${err?.response?.data?.error || 'Tente novamente.'}`);
  } finally {
    consentModalLoading.value = false;
  }
};

// ── Assinatura digital (canvas) ────────────────────────────
const openSignModal = id => {
  signingConsentId.value = id;
  hasSignature.value = false;
  showSignModal.value = true;
  nextTick(() => clearSignature());
};

let lastX = 0;
let lastY = 0;
const getCanvasCoords = (canvas, e) => {
  const rect = canvas.getBoundingClientRect();
  const clientX = e.touches ? e.touches[0].clientX : e.clientX;
  const clientY = e.touches ? e.touches[0].clientY : e.clientY;
  const scaleX = canvas.width / rect.width;
  const scaleY = canvas.height / rect.height;
  return { x: (clientX - rect.left) * scaleX, y: (clientY - rect.top) * scaleY };
};
const startDrawing = e => {
  isDrawing.value = true;
  const coords = getCanvasCoords(signatureCanvas.value, e);
  lastX = coords.x;
  lastY = coords.y;
};
const draw = e => {
  if (!isDrawing.value || !signatureCanvas.value) return;
  e.preventDefault();
  const canvas = signatureCanvas.value;
  const ctx = canvas.getContext('2d');
  const coords = getCanvasCoords(canvas, e);
  ctx.beginPath();
  ctx.moveTo(lastX, lastY);
  ctx.lineTo(coords.x, coords.y);
  ctx.strokeStyle = '#60a5fa';
  ctx.lineWidth = 2.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.stroke();
  lastX = coords.x;
  lastY = coords.y;
  hasSignature.value = true;
};
const stopDrawing = () => {
  isDrawing.value = false;
};
const clearSignature = () => {
  if (!signatureCanvas.value) return;
  const canvas = signatureCanvas.value;
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  hasSignature.value = false;
};

const confirmSign = async () => {
  if (!hasSignature.value) {
    useAlert('Por favor, assine no campo acima.');
    return;
  }
  consentModalLoading.value = true;
  try {
    // Preferir WebP (menor tamanho), com fallback automático para PNG em browsers antigos
    const blob = signatureCanvas.value.toDataURL('image/webp', 0.85);
    await ConsentsAPI.sign(route.params.patientId, signingConsentId.value, blob);
    showSignModal.value = false;
    await fetchConsents();
    useAlert('Consentimento assinado com sucesso!');
  } catch (err) {
    useAlert(`Erro ao assinar: ${err?.response?.data?.error || 'Tente novamente.'}`);
  } finally {
    consentModalLoading.value = false;
  }
};

const viewConsent = async consent => {
  consentInView.value = consent;
  showViewModal.value = true;
  if (['assinado_localmente', 'assinado_remotamente'].includes(consent.status)) {
    try {
      const { data } = await ConsentsAPI.show(route.params.patientId, consent.id);
      consentInView.value = data;
    } catch (_) {
      // mantém o objeto da listagem se falhar
    }
  }
};

const sendConsentRemote = async consentId => {
  try {
    await ConsentsAPI.sendRemote(route.params.patientId, consentId);
    useAlert('Link para assinatura enviado com sucesso para o WhatsApp do paciente!');
  } catch (error) {
    useAlert('Erro ao enviar link para assinatura.');
  }
};

const revokeConsent = async consentId => {
  // eslint-disable-next-line no-alert
  if (!confirm('Tem certeza que deseja revogar este consentimento? Esta ação não pode ser desfeita.')) return;
  try {
    await ConsentsAPI.revoke?.(route.params.patientId, consentId);
    await fetchConsents();
    useAlert('Consentimento revogado.');
  } catch (error) {
    useAlert('Erro ao revogar consentimento.');
  }
};

const consentStats = computed(() => ({
  total: consents.value.length,
  signed: consents.value.filter(c =>
    ['signed', 'assinado_localmente', 'assinado_remotamente'].includes(c.status)
  ).length,
  pending: consents.value.filter(c => c.status === 'pendente' || !c.status).length,
  expired: consents.value.filter(c => c.status === 'vencido').length,
}));

const consentStatusLabel = status =>
  CONSENT_STATUS_CONFIG[status] || CONSENT_STATUS_CONFIG.pendente;
const consentTypeLabel = type =>
  CONSENT_TYPES.find(t => t.value === type)?.label || type || 'Consentimento';
const signConsentNow = id => openSignModal(id);

onMounted(() => {
  fetchConsents();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Consentimentos e Assinaturas
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Gestão jurídica de termos — LGPD, autorizações de imagem,
          procedimentos estéticos e mais.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <button
          class="btn-primary flex items-center gap-2"
          :class="
            showConsentModal
              ? 'bg-slate-600 hover:bg-slate-500'
              : 'bg-emerald-600 hover:bg-emerald-500'
          "
          @click="
            showConsentModal
              ? (showConsentModal = false)
              : openConsentModal()
          "
        >
          <i
            :class="
              showConsentModal
                ? 'i-lucide-x w-4 h-4'
                : 'i-lucide-plus w-4 h-4'
            "
          />
          {{ showConsentModal ? 'Cancelar' : 'Novo Consentimento' }}
        </button>
      </div>
    </div>

    <!-- KPIs de status -->
    <div class="consent-kpi-grid mb-5">
      <div class="consent-kpi-card">
        <div class="consent-kpi-icon consent-kpi-icon--neutral">
          <i class="i-lucide-files w-4 h-4" />
        </div>
        <div>
          <p class="consent-kpi-label">Total</p>
          <p class="consent-kpi-value">{{ consentStats.total }}</p>
        </div>
      </div>
      <div class="consent-kpi-card consent-kpi-card--green">
        <div class="consent-kpi-icon consent-kpi-icon--green">
          <i class="i-lucide-check-circle w-4 h-4" />
        </div>
        <div>
          <p class="consent-kpi-label consent-kpi-label--green">Assinados</p>
          <p class="consent-kpi-value consent-kpi-value--green">
            {{ consentStats.signed }}
          </p>
        </div>
      </div>
      <div class="consent-kpi-card consent-kpi-card--amber">
        <div class="consent-kpi-icon consent-kpi-icon--amber">
          <i class="i-lucide-clock w-4 h-4" />
        </div>
        <div>
          <p class="consent-kpi-label consent-kpi-label--amber">Pendentes</p>
          <p class="consent-kpi-value consent-kpi-value--amber">
            {{ consentStats.pending }}
          </p>
        </div>
      </div>
      <div class="consent-kpi-card consent-kpi-card--red">
        <div class="consent-kpi-icon consent-kpi-icon--red">
          <i class="i-lucide-alert-triangle w-4 h-4" />
        </div>
        <div>
          <p class="consent-kpi-label consent-kpi-label--red">Vencidos</p>
          <p class="consent-kpi-value consent-kpi-value--red">
            {{ consentStats.expired }}
          </p>
        </div>
      </div>
    </div>

    <!-- FORMULÁRIO INLINE: Novo Consentimento -->
    <div v-if="showConsentModal" class="reg-section mb-5">
      <div class="reg-section-toggle consent-form-header">
        <div class="reg-section-toggle-left">
          <div class="reg-section-icon reg-icon-green">
            <i class="i-lucide-plus-circle w-4 h-4" />
          </div>
          <div>
            <span class="reg-section-title">Novo Consentimento</span>
            <span class="reg-section-subtitle"
              >Preencha os dados e o conteúdo do termo</span
            >
          </div>
        </div>
        <button
          class="docs-modal-close"
          title="Fechar"
          @click="showConsentModal = false"
        >
          <i class="i-lucide-x w-4 h-4" />
        </button>
      </div>

      <div class="reg-section-body">
        <div class="grid grid-cols-12 gap-4">
          <div class="col-span-4 form-group">
            <label class="form-label"
              >Tipo de Consentimento <span class="reg-required">*</span></label
            >
            <select
              v-model="newConsentForm.consent_type"
              class="form-input"
              @change="onConsentTypeChange"
            >
              <option value="" disabled>Selecione o tipo...</option>
              <option
                v-for="type in CONSENT_TYPES"
                :key="type.value"
                :value="type.value"
              >
                {{ type.label }}
              </option>
            </select>
            <p
              v-if="consentTypeDetail"
              class="text-xs text-slate-500 mt-1.5 leading-snug"
            >
              {{ consentTypeDetail.description }}
            </p>
          </div>
          <div class="col-span-5 form-group">
            <label class="form-label">Título do Documento</label>
            <input
              v-model="newConsentForm.title"
              type="text"
              placeholder="Ex: Termo de Consentimento para Botox"
              class="form-input"
            />
          </div>
          <div class="col-span-3 form-group">
            <label class="form-label">Validade</label>
            <select v-model="newConsentForm.expires_in_months" class="form-input">
              <option :value="1">1 mês</option>
              <option :value="3">3 meses</option>
              <option :value="6">6 meses</option>
              <option :value="12">12 meses (1 ano)</option>
              <option :value="24">24 meses (2 anos)</option>
              <option :value="60">60 meses (5 anos)</option>
              <option :value="0">Sem vencimento</option>
            </select>
          </div>
        </div>

        <div class="form-group">
          <label class="form-label"
            >Observações Adicionais
            <span class="text-slate-600">(opcional)</span></label
          >
          <input
            v-model="newConsentForm.observations"
            type="text"
            placeholder="Ex: Aplicação na região frontal e glabela — sessão 1/3"
            class="form-input"
          />
        </div>

        <div class="form-group">
          <div class="flex items-center justify-between mb-1.5">
            <label class="form-label"
              >Conteúdo do Termo
              <span class="text-slate-600 font-normal ml-1"
                >(editável — clique para personalizar)</span
              >
            </label>
            <span v-if="newConsentForm.body" class="text-xs text-slate-600">
              {{ newConsentForm.body.length }} caracteres
            </span>
          </div>
          <textarea
            v-model="newConsentForm.body"
            rows="20"
            placeholder="Selecione um tipo de consentimento acima para pré-preencher o template..."
            class="form-input font-mono leading-relaxed resize-y"
            style="min-height: 400px"
          />
        </div>

        <div class="flex items-center justify-between pt-2 border-t border-white/5">
          <p class="text-xs text-slate-500 flex items-center gap-1.5">
            <i class="i-lucide-info w-3 h-3" />
            O consentimento será criado como
            <strong class="text-amber-400">pendente</strong> até ser assinado
          </p>
          <div class="flex gap-3">
            <button class="btn-secondary" @click="showConsentModal = false">
              Cancelar
            </button>
            <button
              class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
              :disabled="consentModalLoading || !newConsentForm.consent_type"
              @click="createConsent"
            >
              <i
                v-if="consentModalLoading"
                class="i-lucide-loader-2 animate-spin w-4 h-4"
              />
              <i v-else class="i-lucide-file-plus w-4 h-4" />
              {{ consentModalLoading ? 'Criando...' : 'Criar Consentimento' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Loading state -->
    <div v-if="consentLoading" class="flex items-center justify-center py-16">
      <div class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin" />
    </div>

    <!-- Empty state -->
    <div
      v-else-if="!consents || consents.length === 0"
      class="reg-section"
    >
      <div class="proc-empty-state">
        <div class="proc-empty-icon">
          <i class="i-lucide-file-signature w-5 h-5" />
        </div>
        <p class="proc-empty-text">Nenhum consentimento registrado</p>
        <p class="proc-empty-hint">
          Clique em "Novo Consentimento" para adicionar o primeiro termo
        </p>
      </div>
    </div>

    <!-- Tabela de Consentimentos -->
    <div v-else class="reg-section">
      <div class="reg-section-toggle consent-form-header">
        <div class="reg-section-toggle-left">
          <div class="reg-section-icon reg-icon-purple">
            <i class="i-lucide-file-signature w-4 h-4" />
          </div>
          <div>
            <span class="reg-section-title">Termos Registrados</span>
            <span class="reg-section-subtitle"
              >Histórico de consentimentos do paciente</span
            >
          </div>
        </div>
        <span class="proc-count-badge">{{ consents.length }}</span>
      </div>

      <div class="proc-table-wrap">
        <table class="proc-table">
          <thead>
            <tr class="proc-table-head">
              <th>Documento</th>
              <th>Categoria</th>
              <th>Validade</th>
              <th>Status</th>
              <th class="text-right">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="consent in consents"
              :key="consent.id"
              class="proc-table-row"
            >
              <td class="proc-table-cell">
                <div class="flex items-center gap-3">
                  <div class="consent-doc-icon">
                    <i class="i-lucide-file-signature w-3.5 h-3.5" />
                  </div>
                  <div>
                    <p class="proc-cell-primary">
                      {{ consent.title || 'Termo de Consentimento' }}
                    </p>
                    <p class="proc-cell-secondary">
                      <i class="i-lucide-calendar w-2.5 h-2.5 mr-0.5" />
                      {{
                        consent.created_at ? formatDate(consent.created_at) : '—'
                      }}
                      <span
                        v-if="consent.version"
                        class="ml-2 text-slate-600"
                        >v{{ consent.version }}</span
                      >
                    </p>
                  </div>
                </div>
              </td>

              <td class="proc-table-cell">
                <span class="proc-cell-secondary">{{
                  consentTypeLabel(consent.document_type)
                }}</span>
              </td>

              <td class="proc-table-cell">
                <span
                  v-if="consent.expires_at"
                  class="proc-cell-secondary flex items-center gap-1"
                >
                  <i class="i-lucide-timer w-2.5 h-2.5" />
                  {{ formatDate(consent.expires_at) }}
                </span>
                <span v-else class="proc-cell-secondary">—</span>
              </td>

              <td class="proc-table-cell">
                <div class="flex flex-col gap-1 items-start">
                  <span
                    class="docs-status-badge"
                    :class="consentStatusLabel(consent.status).cls"
                  >
                    <i
                      :class="consentStatusLabel(consent.status).icon"
                      class="w-3 h-3 mr-1"
                    />
                    {{ consentStatusLabel(consent.status).label.toUpperCase() }}
                  </span>
                  <span
                    v-if="consent.integrity_hash"
                    class="text-[10px] text-slate-500 flex items-center gap-1"
                  >
                    <i class="i-lucide-fingerprint w-2.5 h-2.5" />
                    Hash: {{ consent.integrity_hash?.slice(0, 8) }}...
                  </span>
                  <span
                    v-if="consent.signed_at"
                    class="text-[10px] text-slate-500 flex items-center gap-1"
                  >
                    <i class="i-lucide-clock w-2.5 h-2.5" />
                    {{ formatDate(consent.signed_at) }}
                  </span>
                </div>
              </td>

              <td class="proc-table-cell text-right">
                <div class="consent-actions-group">
                  <button
                    class="consent-action-btn"
                    title="Visualizar termo"
                    @click="viewConsent(consent)"
                  >
                    <i class="i-lucide-eye w-3.5 h-3.5" />
                    <span>Ver</span>
                  </button>
                  <template
                    v-if="
                      !['signed', 'assinado_localmente', 'assinado_remotamente', 'revogado'].includes(consent.status)
                    "
                  >
                    <button
                      class="consent-action-btn consent-action-btn--blue"
                      title="Enviar link de assinatura por WhatsApp"
                      @click="sendConsentRemote(consent.id)"
                    >
                      <i class="i-lucide-smartphone w-3.5 h-3.5" />
                      <span>Enviar</span>
                    </button>
                    <button
                      class="consent-action-btn consent-action-btn--green"
                      title="Assinar presencialmente"
                      @click="signConsentNow(consent.id)"
                    >
                      <i class="i-lucide-pen-tool w-3.5 h-3.5" />
                      <span>Assinar</span>
                    </button>
                  </template>
                  <template
                    v-if="['signed', 'assinado_localmente', 'assinado_remotamente'].includes(consent.status)"
                  >
                    <button
                      class="consent-action-btn consent-action-btn--purple"
                      title="Ver integridade"
                      @click="viewConsent(consent)"
                    >
                      <i class="i-lucide-shield-check w-3.5 h-3.5" />
                      <span>Hash</span>
                    </button>
                    <button
                      class="consent-action-btn consent-action-btn--danger"
                      title="Revogar consentimento"
                      @click="revokeConsent(consent.id)"
                    >
                      <i class="i-lucide-x-circle w-3.5 h-3.5" />
                      <span>Revogar</span>
                    </button>
                  </template>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- MODAL: Assinatura Digital -->
    <div
      v-if="showSignModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
      @click.self="showSignModal = false"
    >
      <div class="consent-sign-modal">
        <div class="docs-modal-header">
          <div class="flex items-center gap-3">
            <div class="consent-modal-icon consent-modal-icon--green">
              <i class="i-lucide-pen-tool w-4 h-4" />
            </div>
            <div>
              <h4 class="text-base font-semibold text-slate-100">
                Assinatura Digital
              </h4>
              <p class="text-xs text-slate-500 mt-0.5">
                Assine com o dedo ou mouse no campo abaixo
              </p>
            </div>
          </div>
          <button class="docs-modal-close" @click="showSignModal = false">
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </div>

        <div class="docs-modal-body">
          <div class="consent-canvas-wrap">
            <canvas
              ref="signatureCanvas"
              width="600"
              height="200"
              class="consent-canvas"
              @mousedown="startDrawing"
              @mousemove="draw"
              @mouseup="stopDrawing"
              @mouseleave="stopDrawing"
              @touchstart.prevent="startDrawing"
              @touchmove.prevent="draw"
              @touchend="stopDrawing"
            />
            <div v-if="!hasSignature" class="consent-canvas-hint">
              <i class="i-lucide-pen-line w-5 h-5 mb-1" />
              <p>Assine aqui</p>
            </div>
          </div>

          <div class="consent-canvas-footer">
            <button class="consent-clear-btn" @click="clearSignature">
              <i class="i-lucide-rotate-ccw w-3 h-3" /> Limpar
            </button>
            <p class="consent-hash-hint">
              <i class="i-lucide-shield w-3 h-3" />
              Hash SHA-256 gerado automaticamente
            </p>
          </div>
        </div>

        <div class="docs-modal-footer">
          <button class="btn-secondary" @click="showSignModal = false">
            Cancelar
          </button>
          <button
            class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2 disabled:opacity-50"
            :disabled="consentModalLoading || !hasSignature"
            @click="confirmSign"
          >
            <i
              v-if="consentModalLoading"
              class="i-lucide-loader-2 animate-spin w-4 h-4"
            />
            <i v-else class="i-lucide-check-circle w-4 h-4" />
            Confirmar Assinatura
          </button>
        </div>
      </div>
    </div>

    <!-- MODAL: Visualizar Consentimento -->
    <div
      v-if="showViewModal && consentInView"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md"
      @click.self="showViewModal = false"
    >
      <div class="consent-view-modal">
        <div class="docs-modal-header">
          <div class="flex items-center gap-3">
            <div class="consent-modal-icon consent-modal-icon--purple">
              <i class="i-lucide-file-signature w-4 h-4" />
            </div>
            <div>
              <h4 class="text-base font-semibold text-slate-100">
                {{ consentInView.title || 'Termo de Consentimento' }}
              </h4>
              <div class="flex items-center gap-3 mt-0.5">
                <span
                  class="docs-status-badge"
                  :class="consentStatusLabel(consentInView.status).cls"
                >
                  {{ consentStatusLabel(consentInView.status).label }}
                </span>
                <span class="text-xs text-slate-500">{{
                  formatDate(consentInView.created_at)
                }}</span>
              </div>
            </div>
          </div>
          <button class="docs-modal-close" @click="showViewModal = false">
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </div>

        <div class="docs-modal-body">
          <div class="consent-view-body">
            <p class="consent-view-text">
              {{ consentInView.body || '(Conteúdo não disponível)' }}
            </p>
          </div>

          <div
            v-if="['signed', 'assinado_localmente', 'assinado_remotamente'].includes(consentInView.status)"
            class="consent-audit-block"
          >
            <p class="consent-audit-title">Auditoria Forense</p>
            <div class="consent-audit-row consent-audit-row--green">
              <i class="i-lucide-check-circle w-3.5 h-3.5" />
              Assinado em {{ formatDate(consentInView.signed_at) }}
            </div>
            <div v-if="consentInView.integrity_hash" class="consent-audit-row">
              <i class="i-lucide-fingerprint w-3.5 h-3.5 flex-shrink-0 mt-0.5" />
              <span class="font-mono break-all">{{
                consentInView.integrity_hash
              }}</span>
            </div>
            <div
              v-if="consentInView.signed_ip"
              class="consent-audit-row consent-audit-row--muted"
            >
              <i class="i-lucide-map-pin w-3.5 h-3.5" />
              IP: {{ consentInView.signed_ip }}
            </div>

            <div
              v-if="
                consentInView.signature_image_url || consentInView.signature_blob
              "
              class="consent-sig-preview"
            >
              <p class="consent-sig-label">Assinatura registrada:</p>
              <div class="consent-sig-frame">
                <img
                  :src="consentInView.signature_image_url || consentInView.signature_blob"
                  alt="Assinatura"
                  class="consent-sig-img"
                />
              </div>
            </div>
          </div>
        </div>

        <div class="docs-modal-footer">
          <button
            v-if="
              !['signed', 'assinado_localmente', 'assinado_remotamente', 'revogado'].includes(consentInView.status)
            "
            class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2"
            @click="
              signConsentNow(consentInView.id);
              showViewModal = false;
            "
          >
            <i class="i-lucide-pen-tool w-4 h-4" /> Assinar Agora
          </button>
          <button class="btn-secondary" @click="showViewModal = false">
            Fechar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ═══════════════════════════════════════════
   CONSENTIMENTOS — estilos exclusivos
═══════════════════════════════════════════ */

/* Cabeçalho não-interativo das seções de consentimento */
.consent-form-header {
  cursor: default;
}

/* Grid dos KPI cards */
.consent-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 14px;
}

/* KPI card base */
.consent-kpi-card {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 16px 18px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
  transition: background 0.15s;
}
.consent-kpi-card:hover {
  background: rgba(255, 255, 255, 0.05);
}

/* KPI card variants */
.consent-kpi-card--green {
  border-color: rgba(74, 222, 128, 0.15);
}
.consent-kpi-card--amber {
  border-color: rgba(251, 191, 36, 0.15);
}
.consent-kpi-card--red {
  border-color: rgba(248, 113, 113, 0.15);
}

/* KPI icon */
.consent-kpi-icon {
  width: 36px;
  height: 36px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.consent-kpi-icon--neutral {
  background: rgba(100, 116, 139, 0.12);
  color: #64748b;
}
.consent-kpi-icon--green {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
}
.consent-kpi-icon--amber {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
}
.consent-kpi-icon--red {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
}

/* KPI label & value */
.consent-kpi-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #64748b;
  margin: 0;
}
.consent-kpi-value {
  font-size: 24px;
  font-weight: 700;
  color: #e2e8f0;
  margin: 2px 0 0;
  line-height: 1;
}

/* Label/value color variants */
.consent-kpi-label--green {
  color: #4ade80;
}
.consent-kpi-label--amber {
  color: #fbbf24;
}
.consent-kpi-label--red {
  color: #f87171;
}
.consent-kpi-value--green {
  color: #4ade80;
}
.consent-kpi-value--amber {
  color: #fbbf24;
}
.consent-kpi-value--red {
  color: #f87171;
}

/* Ícone de documento na tabela */
.consent-doc-icon {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgba(168, 85, 247, 0.1);
  border: 1px solid rgba(168, 85, 247, 0.18);
  color: #c084fc;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

/* Grupo de botões de ação */
.consent-actions-group {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
}

/* Botão de ação com label — base */
.consent-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 5px 10px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: transparent;
  color: #64748b;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  transition:
    background 0.14s,
    color 0.14s,
    border-color 0.14s;
  white-space: nowrap;
}
.consent-action-btn:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #94a3b8;
  border-color: rgba(255, 255, 255, 0.12);
}

/* Variantes semânticas */
.consent-action-btn--green:hover {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
  border-color: rgba(34, 197, 94, 0.2);
}
.consent-action-btn--blue:hover {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}
.consent-action-btn--purple:hover {
  background: rgba(168, 85, 247, 0.1);
  color: #c084fc;
  border-color: rgba(168, 85, 247, 0.2);
}
.consent-action-btn--danger:hover {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.2);
}

/* Ícone do modal de consentimento */
.consent-modal-icon {
  width: 36px;
  height: 36px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.consent-modal-icon--green {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
}
.consent-modal-icon--purple {
  background: rgba(168, 85, 247, 0.1);
  color: #c084fc;
}

/* Modal de assinatura */
.consent-sign-modal {
  background: #111318;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 18px;
  box-shadow: 0 32px 80px rgba(0, 0, 0, 0.5);
  width: 100%;
  max-width: 540px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* Modal de visualização */
.consent-view-modal {
  background: #111318;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 18px;
  box-shadow: 0 32px 80px rgba(0, 0, 0, 0.5);
  width: 100%;
  max-width: 640px;
  max-height: 85vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* Área do canvas de assinatura */
.consent-canvas-wrap {
  position: relative;
  border-radius: 12px;
  border: 2px dashed rgba(255, 255, 255, 0.1);
  background: rgba(0, 0, 0, 0.2);
  aspect-ratio: 16/5;
  overflow: hidden;
}
.consent-canvas {
  width: 100%;
  height: 100%;
  display: block;
  cursor: crosshair;
  touch-action: none;
}
.consent-canvas-hint {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  color: #334155;
  font-size: 13px;
}

/* Footer do canvas */
.consent-canvas-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 10px;
}
.consent-clear-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  color: #64748b;
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 4px 6px;
  border-radius: 6px;
  transition:
    color 0.15s,
    background 0.15s;
}
.consent-clear-btn:hover {
  color: #cbd5e1;
  background: rgba(255, 255, 255, 0.05);
}
.consent-hash-hint {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  color: #475569;
  margin: 0;
}

/* Corpo do termo (visualização) */
.consent-view-body {
  background: rgba(0, 0, 0, 0.15);
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 10px;
  padding: 16px 18px;
  max-height: 340px;
  overflow-y: auto;
}
.consent-view-text {
  font-size: 13px;
  color: #94a3b8;
  line-height: 1.7;
  white-space: pre-wrap;
  font-family: 'SF Mono', 'Fira Code', monospace;
  margin: 0;
}

/* Bloco de auditoria forense */
.consent-audit-block {
  background: rgba(34, 197, 94, 0.04);
  border: 1px solid rgba(34, 197, 94, 0.12);
  border-radius: 10px;
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.consent-audit-title {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: #475569;
  margin: 0 0 4px;
}
.consent-audit-row {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  font-size: 12px;
  color: #94a3b8;
}
.consent-audit-row--green {
  color: #4ade80;
}
.consent-audit-row--muted {
  color: #64748b;
}

/* Preview da assinatura visual */
.consent-sig-preview {
  margin-top: 12px;
}
.consent-sig-label {
  font-size: 11px;
  color: #475569;
  margin: 0 0 8px;
}
.consent-sig-frame {
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: rgba(0, 0, 0, 0.2);
  padding: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
}
.consent-sig-img {
  max-height: 96px;
  object-fit: contain;
}
</style>
