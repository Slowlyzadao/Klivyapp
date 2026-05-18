import { onMounted, onBeforeUnmount } from 'vue';

// Mostra o bubble do widget Chatwoot enquanto o componente estiver montado.
//
// Estratégia de duas camadas (mais robusta que confiar só na API do SDK):
//   1. Adiciona/remove a class `klivy-help-active` no <body>. O CSS em
//      `app/views/layouts/vueapp.html.erb` esconde o bubble por padrão e só
//      o exibe quando essa class está no body. Funciona mesmo se o SDK
//      ainda não carregou ou se `toggleBubbleVisibility` falhar.
//   2. Chama `window.$chatwoot.toggleBubbleVisibility('show'|'hide')` quando
//      disponível — mantém o estado interno do SDK consistente, importante
//      quando o usuário clica para abrir o iframe.
const BODY_CLASS = 'klivy-help-active';

export function useChatBubble() {
  const show = () => {
    document.body.classList.add(BODY_CLASS);
    window.$chatwoot?.toggleBubbleVisibility('show');
  };
  const hide = () => {
    document.body.classList.remove(BODY_CLASS);
    window.$chatwoot?.toggleBubbleVisibility('hide');
  };

  onMounted(show);
  onBeforeUnmount(hide);

  return { show, hide };
}
