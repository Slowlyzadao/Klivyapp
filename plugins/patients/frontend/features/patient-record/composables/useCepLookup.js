/**
 * useCepLookup — autosearch ViaCEP com flag de "dirty" para distinguir
 * mudanças do usuário vs mudanças vindas de fetch inicial do paciente.
 *
 *   • `markCepDirty()` — chame no `@input` do CEP (usuário digitou).
 *   • `searchCep(forceOverwrite)` — bate em ViaCEP. `force=true` sobrescreve
 *     todos os campos; `false` (autosearch) só preenche os vazios.
 *
 * O watcher de zip_code roda externamente no caller (precisa do address ref).
 * Aqui devolvemos apenas a função e a flag.
 */

import { ref } from 'vue';

export function useCepLookup() {
  const cepUserDirty = ref(false);

  const markCepDirty = () => {
    cepUserDirty.value = true;
  };

  const searchCep = async (address, forceOverwrite = false) => {
    if (!address) return;
    const cep = String(address.zip_code || '').replace(/\D/g, '');
    if (cep.length !== 8) return;
    try {
      const resp = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
      const data = await resp.json();
      if (data.erro) return;
      const fill = (key, val) => {
        if (!val) return;
        if (forceOverwrite || !address[key]) {
          // eslint-disable-next-line no-param-reassign
          address[key] = val;
        }
      };
      fill('street', data.logradouro);
      fill('neighborhood', data.bairro);
      fill('city', data.localidade);
      fill('state', data.uf);
    } catch (e) {
      // Silent fallback: sem internet ou ViaCEP fora — preenche manual.
    }
  };

  return {
    cepUserDirty,
    markCepDirty,
    searchCep,
  };
}
