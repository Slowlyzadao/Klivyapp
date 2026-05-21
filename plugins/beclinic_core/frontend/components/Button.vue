<script setup>
/**
 * Button — wrapper fininho do botão nativo do Chatwoot
 * (`dashboard/components-next/button/Button.vue`).
 *
 * Existe para dar um caminho estável e descobrível dentro dos plugins do
 * Klivy. Plugins devem SEMPRE importar daqui em vez de replicar `<button
 * class="btn-primary">` ou definir SCSS próprio.
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
 *   <BeclinicButton label="Salvar" />                              <!-- solid blue md -->
 *   <BeclinicButton label="Cancelar" variant="outline" color="slate" />
 *   <BeclinicButton label="Excluir" color="ruby" />
 *   <BeclinicButton label="Anexar" icon="i-lucide-paperclip" variant="faded" color="slate" />
 *   <BeclinicButton icon="i-lucide-x" variant="ghost" color="slate" size="sm" />
 *   <BeclinicButton label="Salvando..." :is-loading="isSaving" />
 *
 * Para padronizar botões existentes que usam `.btn-primary`, `.hdr-btn--primary`,
 * `.tp-btn-submit`, etc., basta trocar o `<button>` por `<BeclinicButton>`
 * passando `color`/`variant` apropriado e remover a classe SCSS local.
 */
import NextButton from 'dashboard/components-next/button/Button.vue';

defineOptions({ inheritAttrs: false });
</script>

<template>
  <NextButton v-bind="$attrs">
    <template v-for="(_, name) in $slots" #[name]="slotData">
      <slot :name="name" v-bind="slotData" />
    </template>
  </NextButton>
</template>
