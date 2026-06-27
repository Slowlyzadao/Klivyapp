<script setup>
/**
 * Badge — pill/chip de status reutilizável global.
 *
 * Uso semântico (preferido):
 *   <Badge label="Concluído"  intent="success" />
 *   <Badge label="Rascunho"   intent="warning" icon="i-lucide-pencil" />
 *   <Badge label="Errata"     intent="danger"  icon="i-lucide-alert-triangle" />
 *   <Badge label="Assinada"   intent="info"    icon="i-lucide-check-circle-2" />
 *   <Badge label="Pendente"   intent="neutral" />
 *
 * Uso por cor explícita:
 *   <Badge label="VIP"        color="violet"  variant="solid" />
 *
 * Props:
 *   label         : texto (obrigatório)
 *   intent        : 'success' | 'warning' | 'danger' | 'info' | 'neutral'
 *   color         : 'blue' | 'emerald' | 'amber' | 'ruby' | 'slate' | 'cyan' | 'violet'
 *   variant       : 'faded' (default) | 'solid'
 *   icon          : i-lucide-* opcional
 *   size          : 'xs' (default) | 'sm'
 *   strikethrough : risca (errata)
 */
import { computed } from 'vue';

const props = defineProps({
  label: { type: String, required: true },
  intent: {
    type: String,
    default: null,
    validator: v =>
      v === null || ['success', 'warning', 'danger', 'info', 'neutral'].includes(v),
  },
  color: {
    type: String,
    default: 'slate',
    validator: v =>
      ['blue', 'emerald', 'amber', 'ruby', 'slate', 'cyan', 'violet', 'pix'].includes(v),
  },
  variant: {
    type: String,
    default: 'faded',
    validator: v => ['faded', 'solid'].includes(v),
  },
  icon: { type: String, default: null },
  size: {
    type: String,
    default: 'xs',
    validator: v => ['xs', 'sm'].includes(v),
  },
  strikethrough: { type: Boolean, default: false },
});

const INTENT_TO_COLOR = {
  success: 'emerald',
  warning: 'amber',
  danger: 'ruby',
  info: 'blue',
  neutral: 'slate',
};

const resolvedColor = computed(() =>
  props.intent ? INTENT_TO_COLOR[props.intent] : props.color
);
</script>

<template>
  <span
    class="bc-badge"
    :class="[
      `bc-badge--${resolvedColor}`,
      `bc-badge--${variant}`,
      `bc-badge--${size}`,
      strikethrough ? 'bc-badge--strike' : '',
    ]"
  >
    <!-- PIX brand icon (auto quando color='pix'). Usa currentColor pra
         herdar a cor do texto — funciona em faded (teal escuro) e solid
         (branco). Substitui o `icon` lucide caso ambos estejam setados. -->
    <svg
      v-if="resolvedColor === 'pix'"
      class="bc-badge__icon bc-badge__pix-icon"
      viewBox="0 0 297 297"
      fill="currentColor"
      aria-hidden="true"
      role="presentation"
    >
      <path d="M231.433 227.02C219.791 227.02 208.84 222.487 200.607 214.257L156.096 169.745C152.971 166.612 147.524 166.621 144.4 169.745L99.7266 214.42C91.4932 222.649 80.5425 227.183 68.8998 227.183H60.1281L116.503 283.556C134.108 301.161 162.653 301.161 180.26 283.556L236.795 227.02H231.433Z" />
      <path d="M68.8992 69.5768C80.5419 69.5768 91.4927 74.1101 99.726 82.3395L144.399 127.021C147.617 130.239 152.87 130.251 156.095 127.017L200.606 82.5023C208.839 74.273 219.79 69.7397 231.433 69.7397H236.794L180.261 13.205C162.653 -4.40167 134.107 -4.40167 116.502 13.205L60.13 69.577L68.8992 69.5768Z" />
      <path d="M283.557 116.501L249.393 82.3373C248.641 82.6386 247.826 82.8266 246.966 82.8266H231.433C223.402 82.8266 215.541 86.084 209.866 91.7626L165.357 136.273C161.192 140.439 155.718 142.523 150.25 142.523C144.777 142.523 139.308 140.439 135.144 136.277L90.4662 91.6C84.7915 85.92 76.9302 82.664 68.8995 82.664H49.7996C48.9849 82.664 48.2236 82.472 47.5049 82.2013L13.205 116.501C-4.40167 134.108 -4.40167 162.652 13.205 180.259L47.5036 214.557C48.2236 214.287 48.9849 214.095 49.7996 214.095H68.8995C76.9302 214.095 84.7915 210.839 90.4662 205.16L135.14 160.487C143.214 152.419 157.29 152.416 165.357 160.49L209.866 204.997C215.541 210.676 223.402 213.933 231.433 213.933H246.966C247.826 213.933 248.641 214.121 249.393 214.422L283.557 180.258C301.162 162.652 301.162 134.108 283.557 116.501Z" />
    </svg>
    <i v-else-if="icon" :class="[icon, 'bc-badge__icon']" />
    {{ label }}
  </span>
</template>

<style scoped>
/* ──────────────────────────────────────────────────────────
   Badge tokens — independentes do Tailwind JIT (classes
   estáticas em SCSS-in-Vue). Cores hex evitam dependência
   de variáveis Tailwind purgadas.
   ────────────────────────────────────────────────────────── */
.bc-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  border-radius: 9999px;
  white-space: nowrap;
  letter-spacing: 0.02em;
  border-width: 1px;
  border-style: solid;
}

.bc-badge__icon {
  width: 12px;
  height: 12px;
  flex-shrink: 0;
}

/* Sizes */
.bc-badge--xs {
  font-size: 11px;
  font-weight: 700;
  padding: 2px 10px;
  line-height: 1.3;
}
.bc-badge--sm {
  font-size: 12px;
  font-weight: 600;
  padding: 4px 12px;
  line-height: 1.3;
}

/* ── Variant: faded (fundo translúcido + borda) ───────────── */
.bc-badge--faded.bc-badge--blue {
  background: rgba(37, 99, 235, 0.10);
  color: #1d4ed8;
  border-color: rgba(37, 99, 235, 0.28);
}
.bc-badge--faded.bc-badge--emerald {
  background: rgba(16, 185, 129, 0.10);
  color: #047857;
  border-color: rgba(16, 185, 129, 0.28);
}
.bc-badge--faded.bc-badge--amber {
  background: rgba(245, 158, 11, 0.12);
  color: #b45309;
  border-color: rgba(245, 158, 11, 0.32);
}
.bc-badge--faded.bc-badge--ruby {
  background: rgba(220, 38, 38, 0.10);
  color: #b91c1c;
  border-color: rgba(220, 38, 38, 0.32);
}
.bc-badge--faded.bc-badge--slate {
  background: rgba(100, 116, 139, 0.10);
  color: #475569;
  border-color: rgba(100, 116, 139, 0.25);
}
.bc-badge--faded.bc-badge--cyan {
  background: rgba(6, 182, 212, 0.10);
  color: #0e7490;
  border-color: rgba(6, 182, 212, 0.28);
}
.bc-badge--faded.bc-badge--violet {
  background: rgba(124, 58, 237, 0.10);
  color: #6d28d9;
  border-color: rgba(124, 58, 237, 0.28);
}
/* PIX — cor oficial do Banco Central (rgb(46, 189, 175) = #2EBDAF). */
.bc-badge--faded.bc-badge--pix {
  background: rgba(46, 189, 175, 0.12);
  color: #1f8a7e;
  border-color: rgba(46, 189, 175, 0.32);
}

/* ── Variant: solid (fundo cheio, texto branco) ──────────── */
.bc-badge--solid {
  color: #ffffff;
}
.bc-badge--solid.bc-badge--blue {
  background: #2563eb;
  border-color: #2563eb;
}
.bc-badge--solid.bc-badge--emerald {
  background: #059669;
  border-color: #059669;
}
.bc-badge--solid.bc-badge--amber {
  background: #d97706;
  border-color: #d97706;
}
.bc-badge--solid.bc-badge--ruby {
  background: #dc2626;
  border-color: #dc2626;
}
.bc-badge--solid.bc-badge--slate {
  background: #475569;
  border-color: #475569;
}
.bc-badge--solid.bc-badge--cyan {
  background: #0891b2;
  border-color: #0891b2;
}
.bc-badge--solid.bc-badge--violet {
  background: #7c3aed;
  border-color: #7c3aed;
}
.bc-badge--solid.bc-badge--pix {
  background: rgb(46, 189, 175);
  border-color: rgb(46, 189, 175);
}

/* ── Strikethrough (errata) ───────────────────────────────── */
.bc-badge--strike {
  text-decoration: line-through;
  opacity: 0.7;
}

/* ── Dark mode adjustments ────────────────────────────────── */
:root.dark .bc-badge--faded.bc-badge--blue {
  background: rgba(59, 130, 246, 0.18);
  color: #93c5fd;
  border-color: rgba(59, 130, 246, 0.4);
}
:root.dark .bc-badge--faded.bc-badge--emerald {
  background: rgba(16, 185, 129, 0.18);
  color: #6ee7b7;
  border-color: rgba(16, 185, 129, 0.4);
}
:root.dark .bc-badge--faded.bc-badge--amber {
  background: rgba(245, 158, 11, 0.18);
  color: #fcd34d;
  border-color: rgba(245, 158, 11, 0.4);
}
:root.dark .bc-badge--faded.bc-badge--ruby {
  background: rgba(220, 38, 38, 0.18);
  color: #fca5a5;
  border-color: rgba(220, 38, 38, 0.4);
}
:root.dark .bc-badge--faded.bc-badge--slate {
  background: rgba(148, 163, 184, 0.15);
  color: #cbd5e1;
  border-color: rgba(148, 163, 184, 0.32);
}
:root.dark .bc-badge--faded.bc-badge--cyan {
  background: rgba(6, 182, 212, 0.18);
  color: #67e8f9;
  border-color: rgba(6, 182, 212, 0.4);
}
:root.dark .bc-badge--faded.bc-badge--violet {
  background: rgba(124, 58, 237, 0.20);
  color: #c4b5fd;
  border-color: rgba(124, 58, 237, 0.4);
}
:root.dark .bc-badge--faded.bc-badge--pix {
  background: rgba(46, 189, 175, 0.20);
  color: #5dd9c8;
  border-color: rgba(46, 189, 175, 0.45);
}
</style>
