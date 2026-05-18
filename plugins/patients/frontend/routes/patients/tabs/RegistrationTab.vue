<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * RegistrationTab — Aba "Cadastro" do prontuário do paciente.
 *
 * Ficha cadastral progressiva: dados pessoais, contato, endereço (com
 * busca automática de CEP), responsável legal, convênio, opt-ins LGPD.
 * Inclui upload de avatar (arquivo ou câmera frontal) com conversão para WebP.
 *
 * Recebe `patient` como prop (Vue passa por referência, então mutações em
 * campos aninhados via v-model propagam automaticamente para o pai).
 * Emite `saved` após persistir no backend para o pai re-fetchar e atualizar
 * o header (nome, idade, status), tags clínicas da aba Geral, etc.
 *
 * Componente extraído de Record.vue (Fase 5 — última extração do refactor).
 */
import { ref, computed, onMounted, onBeforeUnmount, watch, nextTick } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import {
  formatDateBR,
  brToIsoDate,
  maskDateBR,
} from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';

const props = defineProps({
  patient: { type: Object, required: true },
});
const emit = defineEmits(['saved']);

const route = useRoute();

const isLoading = ref(false);
const avatarInputRef = ref(null);

// Helpers
const formatDate = dateStr => {
  if (!dateStr) return '—';
  return formatDateBR(dateStr) || '—';
};
const getInitials = name => {
  if (!name) return '';
  return name.charAt(0).toUpperCase();
};

// ── Avatar / Câmera ────────────────────────────────────────
const showCameraModal = ref(false);
const videoElement = ref(null);
const canvasElement = ref(null);
const capturedPhoto = ref(null);
const cameraStream = ref(null);
const cameraError = ref(false);

const triggerAvatarUpload = () => {
  avatarInputRef.value?.click();
};

const processImageToWebP = (fileOrBlob, targetSize = 300) => {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(fileOrBlob);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      const canvas = document.createElement('canvas');
      const size = Math.min(img.width, img.height);
      const startX = (img.width - size) / 2;
      const startY = (img.height - size) / 2;

      canvas.width = targetSize;
      canvas.height = targetSize;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(
        img,
        startX,
        startY,
        size,
        size,
        0,
        0,
        targetSize,
        targetSize
      );

      canvas.toBlob(
        blob => {
          resolve(
            new File([blob], `avatar_${Date.now()}.webp`, {
              type: 'image/webp',
            })
          );
        },
        'image/webp',
        0.8
      );
    };
    img.onerror = reject;
    img.src = url;
  });
};

const handleAvatarUpload = async event => {
  const file = event.target.files[0];
  if (!file) return;

  try {
    isLoading.value = true;
    const processedFile = await processImageToWebP(file, 300);
    const { data } = await PatientsAPI.updateAvatar(
      route.params.patientId,
      processedFile
    );
    props.patient.avatar_url =
      data.payload?.avatar_url || data.avatar_url || '';
    useAlert('Foto atualizada com sucesso!');
  } catch (error) {
    useAlert('Erro ao atualizar foto.');
  } finally {
    isLoading.value = false;
    if (avatarInputRef.value) avatarInputRef.value.value = '';
  }
};

const startCamera = async () => {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user' },
    });
    cameraStream.value = stream;
    if (videoElement.value) {
      videoElement.value.srcObject = stream;
      videoElement.value.play().catch(
        (
          e // eslint-disable-next-line no-console
        ) => console.error('Error playing video:', e)
      );
    }
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('Error accessing camera:', err);
    cameraError.value = true;
  }
};

const stopCamera = () => {
  if (cameraStream.value) {
    cameraStream.value.getTracks().forEach(track => track.stop());
    cameraStream.value = null;
  }
};
const openCameraModal = async () => {
  showCameraModal.value = true;
  cameraError.value = false;
  capturedPhoto.value = null;
  await nextTick();
  startCamera();
};

const closeCameraModal = () => {
  stopCamera();
  showCameraModal.value = false;
  capturedPhoto.value = null;
};

const capturePhoto = () => {
  if (!videoElement.value || !canvasElement.value) return;
  const video = videoElement.value;
  const canvas = canvasElement.value;

  const size = Math.min(video.videoWidth, video.videoHeight);
  const startX = (video.videoWidth - size) / 2;
  const startY = (video.videoHeight - size) / 2;

  const targetSize = 300;
  canvas.width = targetSize;
  canvas.height = targetSize;
  const ctx = canvas.getContext('2d');

  // A classe .cam-video já espelha o preview para o usuário.
  // Ao desenhar o vídeo original aqui e mostrá-lo em uma img sem scaleX(-1),
  // o usuário terá a foto exata (espelhada/selfie) que acabou de ver.

  ctx.drawImage(
    video,
    startX,
    startY,
    size,
    size,
    0,
    0,
    targetSize,
    targetSize
  );
  capturedPhoto.value = canvas.toDataURL('image/webp', 0.8);
};

const retakePhoto = () => {
  capturedPhoto.value = null;
};

const useCapturedPhoto = async () => {
  if (!capturedPhoto.value) return;

  try {
    isLoading.value = true;

    // Convert base64 to Blob
    const res = await fetch(capturedPhoto.value);
    const blob = await res.blob();
    const file = new File([blob], `avatar_${Date.now()}.webp`, {
      type: 'image/webp',
    });

    const { data } = await PatientsAPI.updateAvatar(
      route.params.patientId,
      file
    );
    props.patient.avatar_url =
      data.payload?.avatar_url || data.avatar_url || '';

    useAlert('Foto de perfil atualizada!');
    closeCameraModal();
  } catch (error) {
    useAlert('Erro ao salvar foto.');
  } finally {
    isLoading.value = false;
  }
};
const editFirstName = ref('');
const editLastName = ref('');

// Seções colapsáveis do cadastro — todas abertas por padrão
const regSections = ref({
  personal: true,
  contact: true,
  address: false,
  admin: false,
});

const toggleRegSection = section => {
  regSections.value[section] = !regSections.value[section];
};

const registrationCompleteness = computed(() => {
  if (!props.patient) return 0;
  const p = props.patient;
  const fields = [
    p.name,
    p.birthdate,
    p.sex,
    p.cpf,
    p.phone,
    p.email,
    p.address?.zip_code,
    p.address?.city,
    p.address?.state,
    p.emergency_contact?.name,
    p.emergency_contact?.phone,
  ];
  const filled = fields.filter(Boolean).length;
  return Math.round((filled / fields.length) * 100);
});

const saveRegistration = async () => {
  try {
    isLoading.value = true;
    // Join first + last name before saving
    props.patient.name = `${editFirstName.value} ${editLastName.value}`.trim();
    const payload = {
      name: props.patient.name,
      social_name: props.patient.social_name || '',
      cpf: props.patient.cpf
        ? String(props.patient.cpf).replace(/\D/g, '')
        : '',
      rg: props.patient.rg
        ? String(props.patient.rg)
            .replace(/[^a-zA-Z0-9]/g, '')
            .toUpperCase()
        : '',
      birthdate: props.patient.birthdate,
      sex: props.patient.sex,
      marital_status: props.patient.marital_status,
      phone: props.patient.phone
        ? '+55' +
          String(props.patient.phone).replace(/\D/g, '').replace(/^55/, '')
        : '',
      email: props.patient.email,
      notes: props.patient.notes || '',
      address: props.patient.address,
      emergency_contact: {
        ...props.patient.emergency_contact,
        phone: props.patient.emergency_contact?.phone
          ? '+55' +
            String(props.patient.emergency_contact.phone)
              .replace(/\D/g, '')
              .replace(/^55/, '')
          : '',
      },
      has_guardian: Boolean(props.patient.has_guardian),
      guardian: props.patient.has_guardian
        ? {
            name: props.patient.guardian?.name || '',
            cpf: props.patient.guardian?.cpf
              ? String(props.patient.guardian.cpf).replace(/\D/g, '')
              : '',
            phone: props.patient.guardian?.phone || '',
            relationship: props.patient.guardian?.relationship || '',
          }
        : { name: '', cpf: '', phone: '', relationship: '' },
      insurance: props.patient.insurance,
      communication_opt_ins: props.patient.communication_opt_ins,
      lgpd_consent: props.patient.lgpd_consent,
      contact_id: props.patient.contact_id,
    };
    await PatientsAPI.update(route.params.patientId, payload);
    await emit('saved'); // Refetches state to trigger Age calculation
    useAlert('Cadastro atualizado com sucesso!');
    // fetchChangeHistory removido — pai cuida via emit saved; // atualiza historico se a aba estiver aberta
  } catch (error) {
    const backendErrors = error?.response?.data?.errors;
    if (Array.isArray(backendErrors) && backendErrors.length > 0) {
      useAlert(`Erro ao atualizar cadastro: ${backendErrors.join('; ')}`);
    } else {
      useAlert('Erro ao atualizar cadastro.');
    }
  } finally {
    isLoading.value = false;
  }
};

const handleCpfInput = event => {
  let value = event.target.value.replace(/\D/g, '');
  if (value.length > 11) value = value.slice(0, 11);
  if (value.length > 9) {
    value = value.replace(/(\d{3})(\d{3})(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
  } else if (value.length > 6) {
    value = value.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
  } else if (value.length > 3) {
    value = value.replace(/(\d{3})(\d{1,3})/, '$1.$2');
  }
  props.patient.cpf = value;
  event.target.value = value;
};

// ── Data de Nascimento — input com máscara DD/MM/YYYY ───────────────────────
// O backend continua armazenando ISO (YYYY-MM-DD); convertemos no frontend.
const birthdateInputDisplay = ref('');

watch(
  () => props.patient?.birthdate,
  iso => {
    birthdateInputDisplay.value = iso ? formatDateBR(iso) : '';
  },
  { immediate: true }
);

const handleBirthdateInput = event => {
  const masked = maskDateBR(event.target.value);
  birthdateInputDisplay.value = masked;
  event.target.value = masked;
  // Só persiste quando o usuário tiver digitado os 10 caracteres
  if (masked.length === 10) {
    const iso = brToIsoDate(masked);
    if (iso) {
      props.patient.birthdate = iso;
    }
  } else if (masked.length === 0) {
    props.patient.birthdate = '';
  }
};

const handleBirthdateBlur = () => {
  // Garante que valores inválidos parciais não fiquem na UI
  if (!props.patient.birthdate) {
    birthdateInputDisplay.value = '';
  } else {
    birthdateInputDisplay.value = formatDateBR(props.patient.birthdate);
  }
};

// ── Validade da Carteirinha — mesmo padrão da Data de Nascimento ────────────
const insuranceValidUntilDisplay = ref('');

watch(
  () => props.patient?.insurance?.validity,
  iso => {
    insuranceValidUntilDisplay.value = iso ? formatDateBR(iso) : '';
  },
  { immediate: true }
);

const handleInsuranceValidUntilInput = event => {
  const masked = maskDateBR(event.target.value);
  insuranceValidUntilDisplay.value = masked;
  event.target.value = masked;
  if (!props.patient.insurance) props.patient.insurance = {};
  if (masked.length === 10) {
    const iso = brToIsoDate(masked);
    if (iso) props.patient.insurance.validity = iso;
  } else if (masked.length === 0) {
    props.patient.insurance.validity = '';
  }
};

const handleInsuranceValidUntilBlur = () => {
  const iso = props.patient?.insurance?.validity;
  insuranceValidUntilDisplay.value = iso ? formatDateBR(iso) : '';
};

// Quando o usuário desmarca "Possui responsável?", limpa os campos
// imediatamente na UI — evita que dados fiquem ocultos em memória e
// reapareçam ao remarcar (estratégia consistente com o backend, que
// também zera o jsonb quando has_guardian = false).
watch(
  () => props.patient?.has_guardian,
  (newVal, oldVal) => {
    if (oldVal === true && newVal === false) {
      props.patient.guardian = {
        name: '',
        cpf: '',
        phone: '',
        relationship: '',
      };
    }
  }
);

// Guardian — handler para CPF mascarado
const handleGuardianCpfInput = event => {
  let value = event.target.value.replace(/\D/g, '');
  if (value.length > 11) value = value.slice(0, 11);
  if (value.length > 9) {
    value = value.replace(/(\d{3})(\d{3})(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
  } else if (value.length > 6) {
    value = value.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
  } else if (value.length > 3) {
    value = value.replace(/(\d{3})(\d{1,3})/, '$1.$2');
  }
  props.patient.guardian.cpf = value;
  event.target.value = value;
};

// ── Opções dos selects da Ficha Cadastral ───────────────────────────────────
const sexOptions = [
  { value: 'feminino', label: 'Feminino' },
  { value: 'masculino', label: 'Masculino' },
  { value: 'outro', label: 'Outro' },
  { value: 'nao_informado', label: 'Não Informado' },
];

const maritalStatusOptions = [
  { value: 'solteiro', label: 'Solteiro(a)' },
  { value: 'casado', label: 'Casado(a)' },
  { value: 'divorciado', label: 'Divorciado(a)' },
  { value: 'viuvo', label: 'Viúvo(a)' },
];

const guardianRelationshipOptions = [
  { value: 'pai', label: 'Pai' },
  { value: 'mae', label: 'Mãe' },
  { value: 'tutor', label: 'Tutor(a)' },
  { value: 'conjuge', label: 'Cônjuge' },
  { value: 'filho', label: 'Filho(a)' },
  { value: 'irmao', label: 'Irmão / Irmã' },
  { value: 'amigo', label: 'Amigo(a)' },
  { value: 'outro', label: 'Outro' },
];

const ufOptions = [
  'AC','AL','AM','AP','BA','CE','DF','ES','GO','MA','MG','MS','MT',
  'PA','PB','PE','PI','PR','RJ','RN','RO','RR','RS','SC','SE','SP','TO',
].map(uf => ({ value: uf, label: uf }));

const insuranceOptions = [
  { value: 'Particular', label: 'Particular' },
  { value: 'Bradesco Saúde', label: 'Bradesco Saúde' },
  { value: 'SulAmérica', label: 'SulAmérica' },
  { value: 'Amil', label: 'Amil' },
  { value: 'Unimed', label: 'Unimed' },
  { value: 'Porto Seguro', label: 'Porto Seguro' },
];

const handleGuardianPhoneInput = event => {
  let value = event.target.value.replace(/\D/g, '');
  if (value.startsWith('55')) value = value.slice(2);
  if (value.length > 11) value = value.slice(0, 11);
  if (value.length > 10) {
    value = value.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  } else if (value.length > 6) {
    value = value.replace(/(\d{2})(\d{4,5})(\d{0,4})/, '($1) $2-$3');
  } else if (value.length > 2) {
    value = value.replace(/(\d{2})(\d{0,5})/, '($1) $2');
  } else if (value.length > 0) {
    value = value.replace(/(\d{0,2})/, '($1');
  }
  props.patient.guardian.phone = value;
  event.target.value = value;
};

const handleRgInput = event => {
  let value = event.target.value.replace(/[^a-zA-Z0-9]/g, '');
  if (value.length > 9) value = value.slice(0, 9);

  if (value.length > 8) {
    value = value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3-$4'
    );
  } else if (value.length > 5) {
    value = value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3'
    );
  } else if (value.length > 2) {
    value = value.replace(/^([a-zA-Z0-9]{2})([a-zA-Z0-9]{1,})/, '$1.$2');
  }

  value = value.toUpperCase();
  props.patient.rg = value;
  event.target.value = value;
};

// ── Busca por telefone (aba Cadastro) — paralela em pacientes + contatos ────
const phoneContactResults = ref([]); // Chatwoot contacts (chat)
const phonePatientResults = ref([]); // Pacientes existentes (detecção de duplicata)
const phoneContactSearching = ref(false);
const phoneContactDropdown = ref(false);
const phoneContactSkipSearch = ref(false);
let phoneContactTimeout = null;

const handlePhoneInput = event => {
  let value = event.target.value.replace(/\D/g, '');
  if (value.startsWith('55')) value = value.slice(2);
  if (value.length > 11) value = value.slice(0, 11);

  if (value.length > 10) {
    value = value.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  } else if (value.length > 6) {
    value = value.replace(/(\d{2})(\d{4,5})(\d{0,4})/, '($1) $2-$3');
  } else if (value.length > 2) {
    value = value.replace(/(\d{2})(\d{0,5})/, '($1) $2');
  } else if (value.length > 0) {
    value = value.replace(/(\d{0,2})/, '($1');
  }

  // Storage = formatted display (e.g. "(64) 92260-7030"). The `+55` country
  // code is added only at save time in saveRegistration, keeping the input
  // and the header chip consistently friendly.
  props.patient.phone = value;

  // For visual binding of the input itself
  event.target.value = value;

  // Busca paralela: pacientes existentes (detecção de duplicata) + contatos do chat
  if (phoneContactSkipSearch.value) {
    phoneContactSkipSearch.value = false;
    return;
  }
  clearTimeout(phoneContactTimeout);
  const rawDigits = value.replace(/\D/g, '');
  if (!rawDigits || rawDigits.length < 3) {
    phoneContactResults.value = [];
    phonePatientResults.value = [];
    phoneContactDropdown.value = false;
    return;
  }
  phoneContactDropdown.value = true;
  phoneContactSearching.value = true;
  phoneContactTimeout = setTimeout(async () => {
    try {
      const [contactResp, patientResp] = await Promise.allSettled([
        ContactAPI.search(rawDigits),
        PatientsAPI.get({ page: 1, perPage: 25, search: rawDigits }),
      ]);

      phoneContactResults.value =
        contactResp.status === 'fulfilled'
          ? contactResp.value.data?.payload || []
          : [];

      // Filtra fora o paciente atualmente aberto (não faz sentido sugerir ele
      // mesmo) e também duplicatas eventuais.
      const currentId = props.patient?.id;
      phonePatientResults.value =
        patientResp.status === 'fulfilled'
          ? (patientResp.value.data?.payload || []).filter(
              p => p.id !== currentId
            )
          : [];
    } finally {
      phoneContactSearching.value = false;
    }
  }, 400);
};

const selectPhoneContact = contact => {
  phoneContactSkipSearch.value = true;
  props.patient.contact_id = contact.id;
  let digits = String(contact.phone_number || '').replace(/\D/g, '');
  if (digits.startsWith('55')) digits = digits.slice(2);
  // Store as formatted display (no `+55` prefix) — saveRegistration adds
  // the country code at submit time.
  props.patient.phone = formatPhoneDisplay(digits);
  if (contact.email && !props.patient.email)
    props.patient.email = contact.email;
  phoneContactDropdown.value = false;
  phoneContactResults.value = [];
  phonePatientResults.value = [];
};

// Clique em paciente existente no dropdown — abre o prontuário dele em vez
// de criar duplicata. O salvamento atual fica descartado (são pacientes
// diferentes e o usuário escolheu pular pra outro).
const selectPhonePatient = existingPatient => {
  phoneContactDropdown.value = false;
  phoneContactResults.value = [];
  phonePatientResults.value = [];
  router.push({
    name: 'patients_dashboard_record',
    params: {
      accountId: route.params.accountId,
      patientId: existingPatient.id,
    },
  });
};

const phoneContactColor = name => {
  const colors = [
    '#6366f1',
    '#8b5cf6',
    '#ec4899',
    '#f43f5e',
    '#f97316',
    '#22c55e',
    '#14b8a6',
    '#3b82f6',
  ];
  if (!name) return colors[0];
  let h = 0;
  for (let i = 0; i < name.length; i += 1)
    h = name.charCodeAt(i) + (h * 32 - h);
  return colors[Math.abs(h) % colors.length];
};

const handleAlternativePhoneInput = event => {
  let value = event.target.value.replace(/\D/g, '');
  if (value.startsWith('55')) value = value.slice(2);
  if (value.length > 11) value = value.slice(0, 11);

  if (value.length > 10) {
    value = value.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  } else if (value.length > 6) {
    value = value.replace(/(\d{2})(\d{4,5})(\d{0,4})/, '($1) $2-$3');
  } else if (value.length > 2) {
    value = value.replace(/(\d{2})(\d{0,5})/, '($1) $2');
  } else if (value.length > 0) {
    value = value.replace(/(\d{0,2})/, '($1');
  }

  if (!props.patient.emergency_contact) {
    props.patient.emergency_contact = {};
  }

  // Same strategy as patient.phone: store formatted display, prepend `+55`
  // only at save time (saveRegistration).
  props.patient.emergency_contact.phone = value;

  event.target.value = value;
};

// Formatter to render DB phone on screen securely
const formatPhoneDisplay = phoneStr => {
  if (!phoneStr) return '';
  let val = String(phoneStr).replace(/\D/g, '');
  if (val.startsWith('55')) val = val.slice(2);
  if (val.length === 11) {
    return val.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  }
  if (val.length === 10) {
    return val.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
  }
  return phoneStr;
};

const formatCpfDisplay = cpfStr => {
  if (!cpfStr) return '';
  let value = String(cpfStr).replace(/\D/g, '');
  if (value.length > 11) value = value.slice(0, 11);
  if (value.length > 9) {
    return value.replace(/(\d{3})(\d{3})(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
  }
  if (value.length > 6) {
    return value.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
  }
  if (value.length > 3) {
    return value.replace(/(\d{3})(\d{1,3})/, '$1.$2');
  }
  return value;
};

const formatRgDisplay = rgStr => {
  if (!rgStr) return '';
  let value = String(rgStr)
    .replace(/[^a-zA-Z0-9]/g, '')
    .toUpperCase();
  if (value.length > 9) value = value.slice(0, 9);
  if (value.length > 8) {
    return value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3-$4'
    );
  }
  if (value.length > 5) {
    return value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3'
    );
  }
  if (value.length > 2) {
    return value.replace(/^([a-zA-Z0-9]{2})([a-zA-Z0-9]{1,})/, '$1.$2');
  }
  return value;
};

// `forceOverwrite=true` substitui campos preenchidos pelo retorno do ViaCEP
// (clique manual na lupa). `false` (autosearch via watcher) preserva valores
// digitados pelo usuário e só preenche se o ViaCEP retornar algo não-vazio,
// evitando que CEPs sem bairro/rua específicos limpem o que o usuário ou um
// fetch anterior já gravou.
const searchCep = async (forceOverwrite = false) => {
  const cep = props.patient.address?.zip_code?.replace(/\D/g, '');
  if (cep && cep.length === 8) {
    try {
      const resp = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
      const data = await resp.json();
      if (!data.erro) {
        if (!props.patient.address) props.patient.address = {};
        const fill = (key, val) => {
          if (!val) return;
          if (forceOverwrite || !props.patient.address[key]) {
            props.patient.address[key] = val;
          }
        };
        fill('street', data.logradouro);
        fill('neighborhood', data.bairro);
        fill('city', data.localidade);
        fill('state', data.uf);
      }
    } catch (e) {
      // do nothing or silent fallback
    }
  }
};

// Flag que distingue mudança de zip_code vinda de fetch (parent) de mudança
// digitada pelo usuário. Watcher só dispara autosearch quando o usuário muda
// o CEP — fetch inicial vem com a flag false e não acessa ViaCEP.
const cepUserDirty = ref(false);
const markCepDirty = () => {
  cepUserDirty.value = true;
};

watch(
  () => props.patient.address?.zip_code,
  newVal => {
    if (newVal) {
      let value = String(newVal).replace(/\D/g, '');
      if (value.length > 8) value = value.slice(0, 8);

      let formatted = value;
      if (value.length > 5) {
        formatted = value.replace(/(\d{5})(\d{1,3})/, '$1-$2');
      }

      if (newVal !== formatted) {
        if (!props.patient.address) props.patient.address = {};
        props.patient.address.zip_code = formatted;
        return; // will trigger watcher again
      }

      if (value.length === 8 && cepUserDirty.value) {
        searchCep(false);
      }
    }
  }
);

// ── Sync first/last name (split de patient.name) ──────────────
const initEditNameFromPatient = () => {
  const parts = (props.patient?.name || '').trim().split(' ');
  editFirstName.value = parts[0] || '';
  editLastName.value = parts.slice(1).join(' ') || '';
};

watch(
  () => props.patient?.name,
  () => initEditNameFromPatient(),
  { immediate: true }
);

// Cleanup: encerrar stream da câmera se desmontar com modal aberto
onBeforeUnmount(() => {
  if (cameraStream.value) {
    cameraStream.value.getTracks().forEach(t => t.stop());
    cameraStream.value = null;
  }
});

onMounted(() => {
  initEditNameFromPatient();
});
</script>

<template>
  <div class="tab-pane fade-in">





            <!-- Header do Cadastro Progressivo -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Ficha Cadastral
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Preenchimento progressivo — salve quando quiser.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <span class="text-xs text-slate-500"
                  >Última alteração: {{ formatDate(patient.updated_at) }}</span
                >
                <button
                  class="btn-primary flex items-center gap-2"
                  @click="saveRegistration"
                >
                  <i class="i-lucide-save w-4 h-4" />
                  Salvar
                </button>
              </div>
            </div>

            <!-- Form layout -->
            <div class="reg-form-grid">
              <!-- ── SEÇÃO 1: DADOS PESSOAIS ── -->
              <div class="reg-section">
                <button
                  class="reg-section-toggle"
                  @click="toggleRegSection('personal')"
                >
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-blue">
                      <i class="i-lucide-user w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title">Dados Pessoais</span>
                      <span class="reg-section-subtitle"
                        >Nome, nascimento, documento</span
                      >
                    </div>
                  </div>
                  <i
                    class="i-lucide-chevron-down w-4 h-4 reg-chevron"
                    :class="{ 'reg-chevron-open': regSections.personal }"
                  />
                </button>

                <div v-if="regSections.personal" class="reg-section-body">
                  <!-- Avatar Upload -->
                  <div class="reg-avatar-row">
                    <div
                      class="reg-avatar-wrapper"
                      @click="triggerAvatarUpload"
                    >
                      <img
                        v-if="patient.avatar_url"
                        :src="patient.avatar_url"
                        class="reg-avatar-img"
                        alt="Avatar do paciente"
                      />
                      <div v-else class="reg-avatar-placeholder">
                        {{ getInitials(patient.name) }}
                      </div>
                      <div class="reg-avatar-overlay">
                        <i class="i-lucide-camera w-5 h-5" />
                      </div>
                    </div>
                    <div class="reg-avatar-info">
                      <p class="text-sm font-medium text-slate-200">
                        Foto de Perfil
                      </p>
                      <p class="text-xs text-slate-500 mt-0.5">
                        JPG ou PNG · máx. 15MB
                      </p>
                      <div class="flex gap-2 mt-3">
                        <button
                          class="btn-secondary btn-xs flex items-center gap-1.5"
                          @click.stop="openCameraModal"
                        >
                          <i class="i-lucide-camera w-3.5 h-3.5" /> Câmera
                        </button>
                        <button
                          class="btn-secondary btn-xs flex items-center gap-1.5"
                          @click.stop="triggerAvatarUpload"
                        >
                          <i class="i-lucide-upload w-3.5 h-3.5" /> Upload
                        </button>
                      </div>
                      <input
                        ref="avatarInputRef"
                        type="file"
                        class="hidden"
                        accept="image/jpeg, image/png, image/gif"
                        @change="handleAvatarUpload"
                      />
                    </div>
                  </div>

                  <div class="reg-divider" />

                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label
                        >Primeiro Nome
                        <span class="reg-required">*</span></label
                      >
                      <input
                        v-model="editFirstName"
                        type="text"
                        class="form-input"
                        placeholder="Gabriel"
                      />
                    </div>
                    <div class="form-group">
                      <label>Sobrenome</label>
                      <input
                        v-model="editLastName"
                        type="text"
                        class="form-input"
                        placeholder="Fernandes"
                      />
                    </div>
                    <div class="form-group">
                      <label>Nome Social</label>
                      <input
                        v-model="patient.social_name"
                        type="text"
                        class="form-input"
                        placeholder="Opcional"
                      />
                    </div>
                  </div>

                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label
                        >Data de Nascimento
                        <span class="reg-required">*</span></label
                      >
                      <input
                        :value="birthdateInputDisplay"
                        type="text"
                        inputmode="numeric"
                        class="form-input"
                        placeholder="DD/MM/AAAA"
                        maxlength="10"
                        autocomplete="bday"
                        @input="handleBirthdateInput"
                        @blur="handleBirthdateBlur"
                      />
                    </div>
                    <div class="form-group">
                      <label>Sexo <span class="reg-required">*</span></label>
                      <FormSelect
                        v-model="patient.sex"
                        :options="sexOptions"
                        placeholder="Selecione"
                      />
                    </div>
                    <div class="form-group">
                      <label>Estado Civil</label>
                      <FormSelect
                        v-model="patient.marital_status"
                        :options="maritalStatusOptions"
                        placeholder="Selecione"
                        clearable
                      />
                    </div>
                  </div>

                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label>CPF <span class="reg-required">*</span></label>
                      <input
                        :value="formatCpfDisplay(patient.cpf)"
                        type="text"
                        class="form-input"
                        placeholder="000.000.000-00"
                        @input="handleCpfInput"
                      />
                    </div>
                    <div class="form-group">
                      <label>RG</label>
                      <input
                        v-model="patient.rg"
                        type="text"
                        class="form-input"
                        placeholder="Ex: 1234567"
                        maxlength="20"
                      />
                    </div>
                  </div>

                  <div class="form-group">
                    <label>Observações</label>
                    <textarea
                      v-model="patient.notes"
                      class="form-input reg-textarea"
                      rows="3"
                      placeholder="Anotações livres sobre o paciente (opcional)"
                      maxlength="2000"
                    />
                  </div>

                  <div class="reg-divider" />

                  <!-- Responsável -->
                  <div
                    class="reg-toggle-row"
                    role="switch"
                    tabindex="0"
                    :aria-checked="Boolean(patient.has_guardian)"
                    @click="patient.has_guardian = !patient.has_guardian"
                    @keydown.space.prevent="
                      patient.has_guardian = !patient.has_guardian
                    "
                    @keydown.enter.prevent="
                      patient.has_guardian = !patient.has_guardian
                    "
                  >
                    <div class="reg-toggle-row-text">
                      <p class="reg-toggle-row-title">Possui responsável?</p>
                      <p class="reg-toggle-row-hint">
                        Ative para pacientes que dependem de um responsável
                        legal (menores, tutelados, etc.)
                      </p>
                    </div>
                    <div
                      class="reg-toggle"
                      :class="{ 'reg-toggle-on': patient.has_guardian }"
                    >
                      <div class="reg-toggle-thumb" />
                    </div>
                  </div>

                  <transition name="reg-collapse">
                    <div v-if="patient.has_guardian" class="reg-guardian-block">
                      <p class="reg-subsection-label">Dados do Responsável</p>
                      <div class="reg-field-grid-2">
                        <div class="form-group">
                          <label
                            >Nome do Responsável
                            <span class="reg-required">*</span></label
                          >
                          <input
                            v-model="patient.guardian.name"
                            type="text"
                            class="form-input"
                            placeholder="Nome completo"
                          />
                        </div>
                        <div class="form-group">
                          <label
                            >Grau de Relacionamento
                            <span class="reg-required">*</span></label
                          >
                          <FormSelect
                            v-model="patient.guardian.relationship"
                            :options="guardianRelationshipOptions"
                            placeholder="Selecione…"
                            clearable
                          />
                        </div>
                      </div>
                      <div class="reg-field-grid-2">
                        <div class="form-group">
                          <label
                            >CPF do Responsável
                            <span class="reg-required">*</span></label
                          >
                          <input
                            :value="formatCpfDisplay(patient.guardian.cpf)"
                            type="text"
                            class="form-input"
                            placeholder="000.000.000-00"
                            @input="handleGuardianCpfInput"
                          />
                        </div>
                        <div class="form-group">
                          <label
                            >Contato (telefone)
                            <span class="reg-required">*</span></label
                          >
                          <input
                            :value="patient.guardian.phone"
                            type="text"
                            inputmode="numeric"
                            class="form-input"
                            placeholder="(00) 00000-0000"
                            @input="handleGuardianPhoneInput"
                          />
                        </div>
                      </div>
                    </div>
                  </transition>
                </div>
              </div>

              <!-- ── SEÇÃO 2: CONTATO ── -->
              <div class="reg-section">
                <button
                  class="reg-section-toggle"
                  @click="toggleRegSection('contact')"
                >
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-green">
                      <i class="i-lucide-phone w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Contato e Comunicação</span
                      >
                      <span class="reg-section-subtitle"
                        >Telefone, e-mail, preferências</span
                      >
                    </div>
                  </div>
                  <i
                    class="i-lucide-chevron-down w-4 h-4 reg-chevron"
                    :class="{ 'reg-chevron-open': regSections.contact }"
                  />
                </button>

                <div v-if="regSections.contact" class="reg-section-body">
                  <div class="reg-field-grid-2">
                    <div class="form-group reg-field-relative">
                      <label>
                        Telefone Principal
                        <span class="reg-badge-wpp">
                          <i class="i-ri-whatsapp-fill w-3 h-3" />
                          WhatsApp
                        </span>
                        <span class="reg-required">*</span>
                      </label>
                      <input
                        type="text"
                        class="form-input"
                        placeholder="(00) 00000-0000"
                        :value="formatPhoneDisplay(patient.phone)"
                        autocomplete="off"
                        @focus="
                          phoneContactDropdown =
                            phoneContactResults.length > 0 ||
                            phonePatientResults.length > 0
                        "
                        @blur="
                          setTimeout(() => {
                            phoneContactDropdown = false;
                          }, 200)
                        "
                        @input="handlePhoneInput"
                      />
                      <!-- Dropdown agrupado: pacientes existentes + contatos do chat -->
                      <div
                        v-if="
                          phoneContactDropdown &&
                          (phoneContactSearching ||
                            phoneContactResults.length > 0 ||
                            phonePatientResults.length > 0)
                        "
                        class="reg-contact-dropdown"
                      >
                        <div
                          v-if="phoneContactSearching"
                          class="reg-dropdown-loading"
                        >
                          Buscando...
                        </div>
                        <template v-else>
                          <!-- Seção: Pacientes encontrados (priority) -->
                          <div
                            v-if="phonePatientResults.length > 0"
                            class="reg-dropdown-section"
                          >
                            <div class="reg-dropdown-section-header">
                              <i
                                class="i-lucide-user-check w-3 h-3 reg-dropdown-section-icon reg-dropdown-section-icon--patient"
                              />
                              Pacientes existentes
                              <span class="reg-dropdown-section-count">{{
                                phonePatientResults.length
                              }}</span>
                            </div>
                            <ul class="reg-dropdown-list">
                              <li
                                v-for="p in phonePatientResults"
                                :key="`pat-${p.id}`"
                                class="reg-dropdown-item reg-dropdown-item--patient"
                                @mousedown.prevent="selectPhonePatient(p)"
                              >
                                <span
                                  v-if="p.avatar_url"
                                  class="reg-item-avatar reg-item-avatar--img"
                                >
                                  <img :src="p.avatar_url" :alt="p.name" />
                                </span>
                                <span
                                  v-else
                                  class="reg-item-avatar"
                                  :style="{
                                    background: phoneContactColor(p.name),
                                  }"
                                >
                                  {{ (p.name || '?')[0].toUpperCase() }}
                                </span>
                                <div class="reg-item-info">
                                  <span class="reg-item-name">
                                    {{ p.name || 'Sem nome' }}
                                  </span>
                                  <span class="reg-item-phone">
                                    {{
                                      formatPhoneDisplay(p.phone) ||
                                      p.phone ||
                                      'Sem telefone'
                                    }}
                                  </span>
                                </div>
                                <i
                                  class="i-lucide-arrow-right w-4 h-4 reg-dropdown-arrow"
                                />
                              </li>
                            </ul>
                          </div>

                          <!-- Divisor entre seções -->
                          <div
                            v-if="
                              phonePatientResults.length > 0 &&
                              phoneContactResults.length > 0
                            "
                            class="reg-dropdown-divider"
                          />

                          <!-- Seção: Contatos do chat -->
                          <div
                            v-if="phoneContactResults.length > 0"
                            class="reg-dropdown-section"
                          >
                            <div class="reg-dropdown-section-header">
                              <i
                                class="i-lucide-message-circle w-3 h-3 reg-dropdown-section-icon reg-dropdown-section-icon--contact"
                              />
                              Contatos do chat
                              <span class="reg-dropdown-section-count">{{
                                phoneContactResults.length
                              }}</span>
                            </div>
                            <ul class="reg-dropdown-list">
                              <li
                                v-for="contact in phoneContactResults"
                                :key="`ct-${contact.id}`"
                                class="reg-dropdown-item"
                                @mousedown.prevent="selectPhoneContact(contact)"
                              >
                                <span
                                  v-if="contact.avatar_url"
                                  class="reg-item-avatar reg-item-avatar--img"
                                >
                                  <img
                                    :src="contact.avatar_url"
                                    :alt="contact.name"
                                  />
                                </span>
                                <span
                                  v-else
                                  class="reg-item-avatar"
                                  :style="{
                                    background: phoneContactColor(contact.name),
                                  }"
                                >
                                  {{ (contact.name || '?')[0].toUpperCase() }}
                                </span>
                                <div class="reg-item-info">
                                  <span class="reg-item-name">{{
                                    contact.name || 'Sem nome'
                                  }}</span>
                                  <span class="reg-item-phone">{{
                                    contact.phone_number
                                  }}</span>
                                </div>
                              </li>
                            </ul>
                          </div>
                        </template>
                      </div>
                    </div>
                    <div class="form-group">
                      <label>Telefone Alternativo</label>
                      <input
                        :value="
                          formatPhoneDisplay(patient.emergency_contact?.phone)
                        "
                        type="text"
                        class="form-input"
                        placeholder="(11) 00000-0000"
                        @input="handleAlternativePhoneInput"
                      />
                    </div>
                  </div>

                  <div class="form-group">
                    <label>E-mail</label>
                    <input
                      v-model="patient.email"
                      type="email"
                      class="form-input"
                      placeholder="paciente@email.com"
                    />
                  </div>

                  <div class="reg-divider" />

                  <p class="reg-subsection-label">Preferências de contato</p>
                  <div class="reg-opt-in-grid">
                    <label class="reg-opt-in-card">
                      <div class="reg-opt-in-info">
                        <i
                          class="i-lucide-message-circle w-4 h-4 text-green-400"
                        />
                        <div>
                          <p class="text-sm font-medium text-slate-200">
                            WhatsApp
                          </p>
                          <p class="text-xs text-slate-500">
                            Lembretes e confirmações
                          </p>
                        </div>
                      </div>
                      <div
                        class="reg-toggle"
                        :class="{
                          'reg-toggle-on':
                            patient.communication_opt_ins.whatsapp,
                        }"
                        @click="
                          patient.communication_opt_ins.whatsapp =
                            !patient.communication_opt_ins.whatsapp
                        "
                      >
                        <div class="reg-toggle-thumb" />
                      </div>
                    </label>
                    <label class="reg-opt-in-card">
                      <div class="reg-opt-in-info">
                        <i class="i-lucide-mail w-4 h-4 text-blue-400" />
                        <div>
                          <p class="text-sm font-medium text-slate-200">
                            E-mail
                          </p>
                          <p class="text-xs text-slate-500">
                            Comprovantes e comunicados
                          </p>
                        </div>
                      </div>
                      <div
                        class="reg-toggle"
                        :class="{
                          'reg-toggle-on': patient.communication_opt_ins.email,
                        }"
                        @click="
                          patient.communication_opt_ins.email =
                            !patient.communication_opt_ins.email
                        "
                      >
                        <div class="reg-toggle-thumb" />
                      </div>
                    </label>
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 3: ENDEREÇO ── -->
              <div class="reg-section">
                <button
                  class="reg-section-toggle"
                  @click="toggleRegSection('address')"
                >
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-amber">
                      <i class="i-lucide-map-pin w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title">Endereço</span>
                      <span class="reg-section-subtitle"
                        >CEP, rua, cidade, estado</span
                      >
                    </div>
                  </div>
                  <i
                    class="i-lucide-chevron-down w-4 h-4 reg-chevron"
                    :class="{ 'reg-chevron-open': regSections.address }"
                  />
                </button>

                <div v-if="regSections.address" class="reg-section-body">
                  <div class="reg-field-grid-cep">
                    <div class="form-group">
                      <label>CEP</label>
                      <div class="input-with-action">
                        <input
                          v-model="patient.address.zip_code"
                          type="text"
                          class="form-input"
                          placeholder="00000-000"
                          @input="markCepDirty"
                        />
                        <button
                          class="btn-icon-inside"
                          @click.prevent="searchCep(true)"
                        >
                          <i class="i-lucide-search w-4 h-4" />
                        </button>
                      </div>
                    </div>
                    <div class="form-group">
                      <label>Rua / Avenida</label>
                      <input
                        v-model="patient.address.street"
                        type="text"
                        class="form-input"
                      />
                    </div>
                  </div>

                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label>Número</label>
                      <input
                        v-model="patient.address.number"
                        type="text"
                        class="form-input"
                      />
                    </div>
                    <div class="form-group">
                      <label>Complemento</label>
                      <input
                        v-model="patient.address.complement"
                        type="text"
                        class="form-input"
                        placeholder="Apto, bloco..."
                      />
                    </div>
                    <div class="form-group">
                      <label>Bairro</label>
                      <input
                        v-model="patient.address.neighborhood"
                        type="text"
                        class="form-input"
                      />
                    </div>
                  </div>

                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label>Cidade</label>
                      <input
                        v-model="patient.address.city"
                        type="text"
                        class="form-input"
                      />
                    </div>
                    <div class="form-group">
                      <label>Estado (UF)</label>
                      <FormSelect
                        v-model="patient.address.state"
                        :options="ufOptions"
                        placeholder="UF"
                        searchable
                        clearable
                      />
                    </div>
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 4: ADMINISTRATIVO ── -->
              <div class="reg-section">
                <button
                  class="reg-section-toggle"
                  @click="toggleRegSection('admin')"
                >
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-purple">
                      <i class="i-lucide-briefcase w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Administrativo e Convênio</span
                      >
                      <span class="reg-section-subtitle"
                        >Plano de saúde, emergência, LGPD</span
                      >
                    </div>
                  </div>
                  <i
                    class="i-lucide-chevron-down w-4 h-4 reg-chevron"
                    :class="{ 'reg-chevron-open': regSections.admin }"
                  />
                </button>

                <div v-if="regSections.admin" class="reg-section-body">
                  <p class="reg-subsection-label">Plano de Saúde / Convênio</p>
                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label>Convênio</label>
                      <FormSelect
                        v-model="patient.insurance.name"
                        :options="insuranceOptions"
                        placeholder="Selecione"
                        clearable
                      />
                    </div>
                    <div class="form-group">
                      <label>Nº da Carteirinha</label>
                      <input
                        v-model="patient.insurance.number"
                        type="text"
                        class="form-input"
                        placeholder="000.000.000"
                      />
                    </div>
                  </div>
                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label>Plano</label>
                      <input
                        v-model="patient.insurance.plan"
                        type="text"
                        class="form-input"
                        placeholder="Ex: Executivo Plus"
                      />
                    </div>
                    <div class="form-group">
                      <label>Validade da Carteirinha</label>
                      <input
                        :value="insuranceValidUntilDisplay"
                        type="text"
                        inputmode="numeric"
                        class="form-input"
                        placeholder="DD/MM/AAAA"
                        maxlength="10"
                        @input="handleInsuranceValidUntilInput"
                        @blur="handleInsuranceValidUntilBlur"
                      />
                    </div>
                  </div>

                  <div class="reg-divider" />

                  <p class="reg-subsection-label">Contato de Emergência</p>
                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label>Nome</label>
                      <input
                        v-model="patient.emergency_contact.name"
                        type="text"
                        class="form-input"
                      />
                    </div>
                    <div class="form-group">
                      <label>Telefone</label>
                      <input
                        :value="formatPhoneDisplay(patient.emergency_contact.phone)"
                        type="text"
                        inputmode="tel"
                        class="form-input"
                        placeholder="(11) 00000-0000"
                        @input="handleAlternativePhoneInput"
                      />
                    </div>
                    <div class="form-group">
                      <label>Grau de Parentesco</label>
                      <input
                        v-model="patient.emergency_contact.relationship"
                        type="text"
                        class="form-input"
                        placeholder="Ex: Cônjuge"
                      />
                    </div>
                  </div>

                  <div class="reg-divider" />

                  <p class="reg-subsection-label">LGPD e Consentimentos</p>
                  <div class="reg-opt-in-grid">
                    <label class="reg-opt-in-card">
                      <div class="reg-opt-in-info">
                        <i
                          class="i-lucide-shield-check w-4 h-4 text-blue-400"
                        />
                        <div>
                          <p class="text-sm font-medium text-slate-200">
                            Termo LGPD
                          </p>
                          <p class="text-xs text-slate-500">
                            Armazenamento de dados médicos
                          </p>
                        </div>
                      </div>
                      <div
                        class="reg-toggle"
                        :class="{
                          'reg-toggle-on': patient.lgpd_consent.accepted,
                        }"
                        @click="
                          patient.lgpd_consent.accepted =
                            !patient.lgpd_consent.accepted
                        "
                      >
                        <div class="reg-toggle-thumb" />
                      </div>
                    </label>
                    <label class="reg-opt-in-card">
                      <div class="reg-opt-in-info">
                        <i class="i-lucide-image w-4 h-4 text-purple-400" />
                        <div>
                          <p class="text-sm font-medium text-slate-200">
                            Uso de Imagem
                          </p>
                          <p class="text-xs text-slate-500">
                            Marketing e redes sociais
                          </p>
                        </div>
                      </div>
                      <div
                        class="reg-toggle"
                        :class="{
                          'reg-toggle-on':
                            patient.lgpd_consent.image_use_accepted,
                        }"
                        @click="
                          patient.lgpd_consent.image_use_accepted =
                            !patient.lgpd_consent.image_use_accepted
                        "
                      >
                        <div class="reg-toggle-thumb" />
                      </div>
                    </label>
                  </div>
                </div>
              </div>
            </div>
          </div>

  <!-- Modal: Tirar Foto (Webcam) — segundo root (Vue 3 permite múltiplas raízes) -->
  <div
    v-if="showCameraModal"
      class="fixed inset-0 z-[99999] flex items-center justify-center bg-black/75 backdrop-blur-md px-4"
      @click.self="closeCameraModal"
    >
      <div class="cam-modal">
        <!-- Header -->
        <div class="cam-modal-header">
          <div class="flex items-center gap-2.5">
            <div class="cam-header-icon">
              <i class="i-lucide-camera w-4 h-4" />
            </div>
            <div>
              <p class="text-sm font-semibold text-n-slate-12 leading-none">
                Tirar Foto
              </p>
              <p class="text-xs text-n-slate-10 mt-0.5">
                Posicione seu rosto no centro
              </p>
            </div>
          </div>
          <button class="cam-close-btn" @click="closeCameraModal">
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </div>

        <!-- Viewfinder -->
        <div class="cam-viewfinder">
          <video
            v-show="!capturedPhoto"
            ref="videoElement"
            class="cam-video"
            autoplay
            playsinline
          />
          <img v-show="capturedPhoto" :src="capturedPhoto" class="cam-video" />
          <canvas ref="canvasElement" class="hidden" />

          <!-- Overlay de guia circular -->
          <div v-if="!capturedPhoto && !cameraError" class="cam-guide-overlay">
            <div class="cam-guide-ring" />
          </div>

          <!-- Erro de câmera -->
          <div v-if="cameraError" class="cam-error-overlay">
            <i class="i-lucide-camera-off w-10 h-10 text-n-red-10 dark:text-n-red-9 mb-3" />
            <p class="text-sm text-n-slate-11 text-center px-4">
              Permissão negada ou câmera não encontrada.
            </p>
          </div>
        </div>

        <!-- Controles -->
        <div class="cam-controls">
          <template v-if="!capturedPhoto">
            <button class="cam-btn-ghost" @click="closeCameraModal">
              Cancelar
            </button>
            <button
              class="cam-btn-capture"
              :disabled="cameraError"
              @click="capturePhoto"
            >
              <span class="cam-shutter" />
            </button>
            <div class="w-20" />
          </template>
          <template v-else>
            <button
              class="cam-btn-ghost flex items-center gap-1.5"
              @click="retakePhoto"
            >
              <i class="i-lucide-refresh-cw w-3.5 h-3.5" /> Repetir
            </button>
            <button
              class="cam-btn-confirm flex items-center gap-2"
              @click="useCapturedPhoto"
            >
              <i class="i-lucide-check w-4 h-4" /> Usar foto
            </button>
          </template>
        </div>
      </div>
    </div>
</template>

<style scoped>

.reg-dropdown-item--patient {
  /* Sutil destaque pra deixar claro que é um paciente já cadastrado */
  background: rgba(var(--blue-9), 0.04);
}

.reg-dropdown-item--patient:hover {
  background: rgba(var(--blue-9), 0.1);
}

.reg-dropdown-arrow {
  color: rgb(var(--slate-9));
  flex-shrink: 0;
  margin-left: auto;
  opacity: 0;
  transition: opacity 0.15s, transform 0.15s;
}

.reg-dropdown-item--patient:hover .reg-dropdown-arrow {
  opacity: 1;
  transform: translateX(2px);
  color: rgb(var(--blue-9));
}

.reg-item-avatar {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 13px;
  font-weight: 600;
  color: #fff;
  flex-shrink: 0;
}

.reg-item-avatar--img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}

.reg-item-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.reg-item-name {
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.reg-item-phone {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* ── Avatar Upload Premium ── */
.reg-avatar-row {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 4px 0;
}

.reg-avatar-wrapper {
  position: relative;
  width: 80px;
  height: 80px;
  flex-shrink: 0;
  cursor: pointer;
  border-radius: 50%;
  overflow: hidden;
}

.reg-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
  border: 2px solid rgba(255, 255, 255, 0.1);
}

.reg-avatar-placeholder {
  width: 100%;
  height: 100%;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #3b82f6, #8b5cf6);
  font-size: 26px;
  font-weight: 700;
  color: #fff;
  border: 2px solid rgba(255, 255, 255, 0.1);
}

.reg-avatar-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  border-radius: 50%;
  opacity: 0;
  transition: opacity 0.2s;
}

.reg-avatar-wrapper:hover .reg-avatar-overlay {
  opacity: 1;
}

.reg-avatar-info {
  flex: 1;
}

/* ── Botões pequenos ── */
.btn-xs {
  padding: 5px 12px !important;
  height: auto !important;
  font-size: 12px !important;
}

/* ── Toggle Switch ── */
.reg-opt-in-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}

@media (max-width: 640px) {
  .reg-opt-in-grid {
    grid-template-columns: 1fr;
  }
}

.reg-opt-in-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 14px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.02);
  cursor: pointer;
  transition:
    border-color 0.15s,
    background 0.15s;
}

.reg-opt-in-card:hover {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.12);
}

.reg-opt-in-info {
  display: flex;
  align-items: center;
  gap: 10px;
}

.reg-toggle {
  width: 38px;
  height: 22px;
  border-radius: 99px;
  background: rgb(206 206 206);
  position: relative;
  flex-shrink: 0;
  transition: background 0.2s;
  cursor: pointer;
}

.reg-toggle-on {
  background: #3b82f6;
}

.reg-toggle-thumb {
  position: absolute;
  top: 3px;
  left: 3px;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: #fff;
  transition: transform 0.2s ease;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.4);
}

.reg-toggle-on .reg-toggle-thumb {
  transform: translateX(16px);
}

/* =====================================
   MODAL DE CÂMERA PREMIUM (Light Mode adaptado)
===================================== */
.cam-modal {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-3));
  border-radius: 20px;
  overflow: hidden;
  width: 100%;
  max-width: 420px;
  box-shadow:
    0 16px 40px rgba(0, 0, 0, 0.16),
    0 0 0 1px rgba(0, 0, 0, 0.05);
}

.cam-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid rgb(var(--slate-3));
  background: rgb(var(--slate-2));
}

.cam-header-icon {
  width: 34px;
  height: 34px;
  border-radius: 10px;
  background: rgba(59, 130, 246, 0.1);
  color: #3b82f6;
  display: flex;
  align-items: center;
  justify-content: center;
}

.cam-close-btn {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-2));
  color: rgb(var(--slate-6));
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition:
    background 0.15s,
    color 0.15s;
  flex-shrink: 0;
}

.cam-close-btn:hover {
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-9));
}

/* Viewfinder: área do vídeo */
.cam-viewfinder {
  position: relative;
  width: 100%;
  aspect-ratio: 1 / 1;
  background: #000;
  overflow: hidden;
}

.cam-video {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
  transform: scaleX(-1);
}

.cam-captured {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

/* Overlay de guia oval para o rosto */
.cam-guide-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  background: rgba(255, 255, 255, 0.15);
}

.cam-guide-ring {
  width: 200px;
  height: 240px;
  border-radius: 50%;
  border: 2px solid rgba(255, 255, 255, 0.8);
  box-shadow:
    0 0 0 9999px rgba(0, 0, 0, 0.35),
    inset 0 0 0 1px rgba(0, 0, 0, 0.2);
}

/* Overlay de erro */
.cam-error-overlay {
  position: absolute;
  inset: 0;
  z-index: 10;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: rgb(var(--slate-2));
}

/* Barra de controles */
.cam-controls {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 20px 24px;
  background: rgb(var(--slate-2));
  border-top: 1px solid rgb(var(--slate-3));
}

/* Botão fantasma (Cancelar / Repetir) */
.cam-btn-ghost {
  min-width: 80px;
  padding: 8px 14px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-6));
  background: transparent;
  border: none;
  cursor: pointer;
  transition:
    color 0.15s,
    background 0.15s;
}

.cam-btn-ghost:hover {
  color: rgb(var(--slate-9));
  background: rgb(var(--slate-2));
}

/* Botão circular de captura (obturador) */
.cam-btn-capture {
  padding: 0;
  width: 68px;
  min-width: 68px;
  max-width: 68px;
  height: 68px;
  min-height: 68px;
  max-height: 68px;
  aspect-ratio: 1 / 1;
  border-radius: 50%;
  background: transparent;
  border: 3px solid rgb(var(--slate-3));
  box-sizing: border-box;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition:
    border-color 0.15s,
    transform 0.1s;
  flex-shrink: 0;
  align-self: center;
}

.cam-btn-capture:hover:not(:disabled) {
  border-color: rgb(var(--slate-4));
  transform: scale(1.04);
}

.cam-btn-capture:active:not(:disabled) {
  transform: scale(0.94);
}

.cam-btn-capture:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}

/* Disco interno do obturador */
.cam-shutter {
  display: block;
  width: 52px;
  min-width: 52px;
  height: 52px;
  min-height: 52px;
  aspect-ratio: 1 / 1;
  border-radius: 50%;
  background: #ffffff;
  border: 1px solid rgb(var(--slate-2));
  flex-shrink: 0;
  transition:
    transform 0.1s,
    background-color 0.1s;
}

.cam-btn-capture:active:not(:disabled) .cam-shutter {
  transform: scale(0.88);
  background: rgb(var(--slate-1));
}

/* Botão confirmar (Usar foto) */
.cam-btn-confirm {
  min-width: 100px;
  padding: 10px 18px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  color: #fff;
  background: #10b981;
  border: none;
  cursor: pointer;
  transition:
    background 0.15s,
    transform 0.1s;
}

.cam-btn-confirm:hover {
  background: #059669;
  transform: scale(1.02);
}

/* ── Input com botão sobreposto (lupa do CEP) ── */
.input-with-action {
  position: relative;
  display: flex;
  align-items: center;
}
.input-with-action .form-input {
  padding-right: 36px;
}
.btn-icon-inside {
  position: absolute;
  right: 8px;
  background: transparent;
  border: none;
  color: rgb(var(--slate-9));
  cursor: pointer;
  padding: 4px;
  border-radius: 4px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.btn-icon-inside:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

/* ── Chevron rotacionado quando seção aberta ── */
.reg-chevron-open {
  transform: rotate(180deg);
}

/* ── Textarea (Observações) ── */
.reg-textarea {
  resize: vertical;
  min-height: 84px;
  font-family: inherit;
  line-height: 1.45;
}

/* ── Toggle row (Possui responsável? e similares) ── */
.reg-toggle-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 14px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  cursor: pointer;
  transition: background 0.15s ease, border-color 0.15s ease;
  user-select: none;
}
.reg-toggle-row:hover {
  background: rgb(var(--slate-3));
  border-color: rgb(var(--slate-5));
}
.reg-toggle-row:focus-visible {
  outline: 2px solid rgb(var(--blue-8));
  outline-offset: 2px;
}
.reg-toggle-row-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.reg-toggle-row-title {
  font-size: 13px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0;
}
.reg-toggle-row-hint {
  font-size: 11px;
  font-weight: 400;
  color: rgb(var(--slate-9));
  margin: 0;
}

/* ── Bloco do Responsável (indentação + agrupamento visual) ── */
.reg-guardian-block {
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 14px 16px;
  margin-left: 6px;
  border-left: 2px solid rgba(59, 130, 246, 0.35);
  background: rgba(59, 130, 246, 0.04);
  border-radius: 0 8px 8px 0;
}

/* ── Animação de collapse ── */
.reg-collapse-enter-active,
.reg-collapse-leave-active {
  transition:
    max-height 220ms ease,
    opacity 180ms ease,
    margin-top 220ms ease;
  overflow: hidden;
}
.reg-collapse-enter-from,
.reg-collapse-leave-to {
  max-height: 0;
  opacity: 0;
  margin-top: 0;
}
.reg-collapse-enter-to,
.reg-collapse-leave-from {
  max-height: 600px;
  opacity: 1;
}

/* ── Badge WhatsApp ── */
.reg-badge-wpp {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  font-weight: 500;
  color: #25d366;
  margin-left: 6px;
  vertical-align: middle;
}
.reg-badge-wpp i {
  color: #25d366;
}

/* ── Dropdown de busca de contato ── */
.reg-field-relative {
  position: relative;
}

.reg-contact-dropdown {
  position: absolute;
  top: calc(100% + 4px);
  left: 0;
  right: 0;
  z-index: 200;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--border-strong));
  border-radius: 10px;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.18);
  overflow: hidden;
}

.reg-dropdown-loading {
  padding: 12px 16px;
  font-size: 13px;
  color: rgb(var(--slate-9));
  text-align: center;
}

.reg-dropdown-list {
  list-style: none;
  margin: 0;
  padding: 4px;
  max-height: 240px;
  overflow-y: auto;
}

.reg-dropdown-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  border-radius: 7px;
  cursor: pointer;
  transition: background 0.15s, color 0.15s;
  color: rgb(var(--slate-12));
}
.reg-dropdown-item:hover {
  background: rgb(var(--slate-3));
}

.reg-dropdown-section + .reg-dropdown-section {
  margin-top: 4px;
}
.reg-dropdown-section-header {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 12px 4px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
}
.reg-dropdown-section-icon--patient {
  color: rgb(var(--blue-9));
}
.reg-dropdown-section-icon--contact {
  color: rgb(var(--slate-9));
}
.reg-dropdown-section-count {
  margin-left: auto;
  font-size: 10px;
  font-weight: 600;
  color: rgb(var(--slate-9));
  background: rgb(var(--slate-3));
  padding: 1px 6px;
  border-radius: 99px;
  letter-spacing: 0;
}
.reg-dropdown-divider {
  height: 1px;
  background: rgb(var(--border-strong));
  margin: 4px 0;
  opacity: 0.5;
}
</style>
