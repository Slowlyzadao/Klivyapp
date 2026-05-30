import { frontendURL } from 'dashboard/helper/URLHelper';
import DocumentsIndex from './documents/DocumentsIndex.vue';

// Rotas do plugin document_templates. Carregadas em
// app/javascript/dashboard/routes/dashboard/dashboard.routes.js junto com
// telemed, patients, agenda etc.
//
// Permissões:
//   - documents_dashboard_index: agent OU administrator (qualquer um vê a lista,
//     mas só admin clica em "Novo template" / "Nova pasta").
//   - documents_dashboard_edit:  só administrator. Backend também valida via
//     DocumentTemplatePolicy (defesa em profundidade).
//
// **Lazy-load do TemplateEditor**: o editor carrega ~1MB de bundle TipTap +
// extensões. A listagem (DocumentsIndex) não usa TipTap, então não vale
// pagar esse custo no first paint. Quando o user clica em "Editar", o Vite
// busca o chunk do editor sob demanda (~200ms na primeira vez, cacheado depois).
export const routes = [
  {
    path: frontendURL('accounts/:accountId/documents'),
    name: 'documents_dashboard_index',
    component: DocumentsIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
  {
    path: frontendURL('accounts/:accountId/documents/:id/edit'),
    name: 'documents_dashboard_edit',
    component: () => import('./documents/TemplateEditor.vue'),
    meta: {
      permissions: ['administrator'],
    },
  },
];
