import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';

export const formatCpf = (cpfStr, { emptyFallback = '' } = {}) => {
  if (!cpfStr) return emptyFallback;
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

export const formatPhone = phoneStr => {
  if (!phoneStr) return '';
  let val = String(phoneStr).replace(/\D/g, '');
  if (val.startsWith('55')) val = val.slice(2);
  // Móvel BR: separa o nono dígito ("9 9999-9999") como recomendado pela Anatel.
  if (val.length === 11) {
    return val.replace(/(\d{2})(\d{1})(\d{4})(\d{4})/, '($1) $2 $3-$4');
  }
  if (val.length === 10) {
    return val.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
  }
  return phoneStr;
};

export const formatDate = (dateStr, fallback = '—') => {
  if (!dateStr) return fallback;
  return formatDateBR(dateStr) || fallback;
};

export const formatSex = sex => {
  if (!sex) return '';
  const lower = sex.toLowerCase();
  if (lower === 'masculino') return 'Masculino';
  if (lower === 'feminino') return 'Feminino';
  return sex;
};

export const hasValidSex = sex => {
  if (!sex) return false;
  const s = String(sex).toLowerCase().trim();
  return ![
    '',
    'não informado',
    'nao_informado',
    'não_informado',
    'null',
  ].includes(s);
};

export const formatInsurance = ins => {
  if (!ins) return null;
  let parsed = ins;
  if (typeof parsed === 'string') {
    if (
      parsed === '—' ||
      parsed === '{}' ||
      parsed === 'null' ||
      parsed.includes('"name":""') ||
      parsed.includes('"name": ""')
    ) {
      return null;
    }
    try {
      parsed = JSON.parse(parsed);
    } catch (e) {
      return parsed;
    }
  }
  if (parsed && typeof parsed === 'object') {
    if (!parsed.name) return null;
    return `${parsed.name}${parsed.plan ? ' - ' + parsed.plan : ''}`;
  }
  return String(parsed);
};

// Mesma lógica do componente canônico `dashboard/components-next/avatar/Avatar.vue`
// pra manter coerência visual entre lista (AS) e prontuário (AS, não A).
// Nomes curtos (≤3 chars) viram iniciais inteiras; senão, primeira letra
// das duas primeiras palavras.
export const getInitials = name => {
  if (!name) return '';
  const cleaned = String(name).trim();
  if (!cleaned) return '';
  if (cleaned.length <= 3) return cleaned.toUpperCase();
  const words = cleaned.split(/\s+/);
  if (words.length === 1) return words[0].charAt(0).toUpperCase();
  return words.slice(0, 2).map(w => w.charAt(0)).join('').toUpperCase();
};
