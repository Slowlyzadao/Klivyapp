<script setup>
/**
 * Button — wrapper fininho do botão nativo do Chatwoot
 * (`dashboard/components-next/button/Button.vue`).
 *
 * Existe para dar um caminho estável e descobrível dentro dos plugins do
 * Klivy. Plugins devem SEMPRE importar daqui em vez de replicar `<button
 * class="btn-primary">` ou definir SCSS próprio.
 *
 * **Fix do ícone "sumido"** (2026-05-23): o NextButton renderiza o ícone via
 * `<Icon :icon="icon" class="flex-shrink-0" />` SEM `width/height` explícitos.
 * Combinado com `min-w-0 truncate gap-2 px-4` do botão, o ícone às vezes vira
 * `width: 0` e desaparece. Wrapper aqui injeta `w-4 h-4 flex-shrink-0` no
 * ícone via slot `#icon` quando a prop `icon` é passada — garante visibilidade
 * sem precisar mexer no core do Chatwoot nem em cada call site.
 *
 * O componente nativo já garante visual consistente:
 *   - rounded-lg (8px)
 *   - alturas: xs=24px, sm=32px, md=40px (default), lg=48px
 *   - cores: blue (default), ruby, amber, slate, teal
 *   - variantes: solid (default), outline, faded, link, ghost
 *   - suporta `icon`, `isLoading`, `trailingIcon`
 *
 * Quando usar cada variant:
 *   - `solid`   → ação primária da tela (Salvar, Confirmar)
 *   - `outline` → ação secundária com borda estável (Editar, Imprimir, Cancelar
 *                 com peso visual). USE quando o botão precisa "anchorar" mesmo
 *                 sem hover — evita o efeito de "encolher" que o `ghost` causa
 *                 ao trocar de fundo transparente pra alpha-2 no hover.
 *   - `faded`   → ação secundária leve com cor da paleta (badge-like)
 *   - `ghost`   → ação terciária invisível em rest, ganha background no hover.
 *                 Bom pra ícones em toolbars; ruim pra botões com label que
 *                 precisam ser facilmente clicáveis sem hover.
 *   - `link`    → texto-link inline
 *
 * Uso:
 *   <BeclinicButton label="Salvar" icon="i-lucide-check" />
 *   <BeclinicButton label="Cancelar" variant="outline" color="slate" />
 *   <BeclinicButton label="Anexar" icon="i-lucide-paperclip" variant="faded" color="slate" />
 *   <BeclinicButton icon="i-lucide-x" variant="ghost" color="slate" size="sm" />
 *   <BeclinicButton label="Salvando..." :is-loading="isSaving" />
 *
 * Caso especial: pra trocar o ícone por algo custom (badge, avatar, etc),
 * use slot `#icon` em vez da prop `:icon`:
 *   <BeclinicButton label="Profissional">
 *     <template #icon><Avatar :name="u.name" :size="16" /></template>
 *   </BeclinicButton>
 */
import { computed, useAttrs, useSlots } from 'vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

defineOptions({ inheritAttrs: false });

const attrs = useAttrs();
const slots = useSlots();

// Tamanho do ícone proporcional ao tamanho do botão. Default md = w-4 h-4 (16px).
const iconSizeClass = computed(() => {
  const size = attrs.size || (attrs.xs === '' || attrs.xs ? 'xs'
    : attrs.sm === '' || attrs.sm ? 'sm'
    : attrs.lg === '' || attrs.lg ? 'lg'
    : 'md');
  return ({
    xs: 'w-3.5 h-3.5',
    sm: 'w-4 h-4',
    md: 'w-4 h-4',
    lg: 'w-5 h-5',
  })[size] || 'w-4 h-4';
});

// Só injeta o slot custom se o usuário passou a prop `icon` E não passou
// slot `#icon` manual. Assim os call sites que já usam slot continuam funcionando.
const shouldInjectIcon = computed(() => Boolean(attrs.icon) && !slots.icon);
</script>

<template>
  <NextButton v-bind="$attrs">
    <template v-if="shouldInjectIcon" #icon>
      <i :class="[attrs.icon, iconSizeClass, 'flex-shrink-0']" />
    </template>
    <template v-for="(_, name) in $slots" #[name]="slotData">
      <slot :name="name" v-bind="slotData" />
    </template>
  </NextButton>
</template>
