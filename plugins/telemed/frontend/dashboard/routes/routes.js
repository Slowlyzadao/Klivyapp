// Routes do plugin Telemed para o dashboard (visão clínica).
// Importadas pelo `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
// (junto com agenda, patients, financial, etc).
import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

// Sala LiveKit do lado clínica. Rota standalone (aberta em window.open) pra
// não bloquear o calendário do dentista enquanto ele atende. Token entregue
// via sessionStorage (não pela URL).
import TelemedRoomPage from '../pages/TelemedRoomPage.vue';

// Aba Teleconsulta no menu lateral (lista + detalhe da consulta finalizada
// com player, transcrição e evolução proposta pela IA).
import TeleconsultaListPage from '../features/teleconsulta/TeleconsultaListPage.vue';
import TeleconsultaDetailPage from '../features/teleconsulta/TeleconsultaDetailPage.vue';

export const routes = [
  {
    // Apenas o profissional responsável passa pela policy `telemedicine_join?`
    // no backend, então o token só é emitido pra ele. Aqui o front aceita
    // o request mesmo que outro usuário acesse a URL: vai falhar no token
    // e mostrar a mensagem.
    path: frontendURL('accounts/:accountId/agenda/telemed/:eventId'),
    name: 'agenda_telemed_room',
    meta: { permissions: [...ROLES, ...CONVERSATION_PERMISSIONS] },
    component: TelemedRoomPage,
  },
  {
    path: frontendURL('accounts/:accountId/teleconsultas'),
    name: 'teleconsultas_index',
    meta: { permissions: [...ROLES, ...CONVERSATION_PERMISSIONS] },
    component: TeleconsultaListPage,
  },
  {
    path: frontendURL('accounts/:accountId/teleconsultas/:eventId'),
    name: 'teleconsulta_detail',
    meta: { permissions: [...ROLES, ...CONVERSATION_PERMISSIONS] },
    component: TeleconsultaDetailPage,
  },
];
