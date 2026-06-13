// Composables pra diálogos de confirmação e prompt — substituem os
// window.confirm/window.prompt nativos do browser por modais do design
// system Klivy (BaseModal).
//
// Padrão promise-based: `await confirm({...})` resolve true/false;
// `await prompt({...})` resolve a string digitada ou null (cancelado).
// Cada componente que precisa instancia seu próprio host e renderiza
// <ConfirmDialog>/<PromptDialog> ligados ao estado retornado.

import { ref } from 'vue';

export function useConfirm() {
  const confirmState = ref({ open: false });
  let resolver = null;

  const confirm = (opts = {}) => {
    confirmState.value = { open: true, variant: 'primary', ...opts };
    return new Promise((resolve) => {
      resolver = resolve;
    });
  };

  const settle = (value) => {
    confirmState.value = { ...confirmState.value, open: false };
    const resolve = resolver;
    resolver = null;
    if (resolve) resolve(value);
  };

  return {
    confirmState,
    confirm,
    onConfirm: () => settle(true),
    onCancel: () => settle(false),
  };
}

export function usePrompt() {
  const promptState = ref({ open: false, value: '' });
  let resolver = null;

  const prompt = (opts = {}) => {
    promptState.value = { open: true, value: opts.defaultValue || '', ...opts };
    return new Promise((resolve) => {
      resolver = resolve;
    });
  };

  const settle = (value) => {
    promptState.value = { ...promptState.value, open: false };
    const resolve = resolver;
    resolver = null;
    if (resolve) resolve(value);
  };

  return {
    promptState,
    prompt,
    onSubmit: (value) => settle(value),
    onCancel: () => settle(null),
  };
}
