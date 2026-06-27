// Carregadores lazy por locale — um chunk por idioma, buscado sob demanda.
// Usado pelo entrypoint de login (v3) para não empacotar os ~40 locales
// up-front. O entrypoint do dashboard segue importando o `./index.js` eager
// (todos os locales) para que o seletor de idioma in-app continue instantâneo.
//
// A lista de códigos espelha EXATAMENTE o allow-list do `./index.js`. Isso é
// proposital: a pasta `./locale/` contém dirs incompletos/stub (zh, am, az,
// et, sh, …) que o `index.js` nunca importou — um glob aberto (`*`) puxaria
// esses stubs quebrados e estouraria o build. Locale novo no upstream que não
// esteja aqui simplesmente cai pro 'en' no login (degradação graciosa).
const localeLoaders = import.meta.glob(
  './locale/{ar,bg,ca,cs,da,de,el,en,es,fa,fi,fr,he,hi,hu,id,it,ja,ko,lv,ml,nl,no,pl,pt,pt_BR,ro,ru,sk,sr,sv,ta,th,tr,uk,vi,zh_CN,zh_TW,is,lt}/index.js'
);

export async function loadLocaleMessages(code) {
  const loader = localeLoaders[`./locale/${code}/index.js`];
  if (!loader) return null;
  const mod = await loader();
  return mod.default;
}
