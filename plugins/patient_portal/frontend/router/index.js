// Vue Router em modo history. Cada rota lazy-carrega uma página em pages/.
import { createRouter, createWebHistory } from 'vue-router';
import { useAuthStore } from '../store/auth';

const routes = [
  // ─── Auth ─────────────────────────────────────────────────────────
  { path: '/login',           name: 'login',           component: () => import('../pages/LoginPage.vue') },
  { path: '/verify',          name: 'verify',          component: () => import('../pages/OtpVerifyPage.vue') },
  { path: '/select-account',  name: 'select-account',  component: () => import('../pages/AccountSelectPage.vue') },
  // Dev-only — login direto via JWT em query (?token=...&next=/path)
  { path: '/dev_login',       name: 'dev-login',       component: () => import('../pages/DevLoginPage.vue') },

  // ─── Termo bloqueante ─────────────────────────────────────────────
  { path: '/consent',         name: 'consent',         component: () => import('../pages/ConsentTermsPage.vue'),
    meta: { requiresAuth: true, skipConsentGate: true } },

  // ─── App principal (com bottom nav) ───────────────────────────────
  { path: '/',                name: 'home',            component: () => import('../pages/HomePage.vue'),         meta: { requiresAuth: true } },
  { path: '/appointments',    name: 'appointments',    component: () => import('../pages/AppointmentsPage.vue'), meta: { requiresAuth: true } },
  { path: '/appointments/new', name: 'appointment-new', component: () => import('../pages/NewAppointmentPage.vue'), meta: { requiresAuth: true } },
  { path: '/appointments/:id', name: 'appointment-detail', component: () => import('../pages/AppointmentDetailPage.vue'), meta: { requiresAuth: true } },
  { path: '/appointments/:id/telemed', name: 'telemed-room', component: () => import('@plugins/telemed/frontend/patient/pages/TelemedicineRoomPage.vue'), meta: { requiresAuth: true } },
  { path: '/health',          name: 'health',          component: () => import('../pages/HealthPage.vue'),       meta: { requiresAuth: true } },
  { path: '/health/document-request', name: 'document-request', component: () => import('../pages/DocumentRequestPage.vue'), meta: { requiresAuth: true } },
  { path: '/health/anamnesis/:id', name: 'anamnesis-detail', component: () => import('../pages/AnamnesisDetailPage.vue'), meta: { requiresAuth: true } },
  { path: '/financial',       name: 'financial',       component: () => import('../pages/FinancialPage.vue'),    meta: { requiresAuth: true } },
  { path: '/financial/installments/:id', name: 'installment-detail', component: () => import('../pages/InstallmentDetailPage.vue'), meta: { requiresAuth: true } },
  { path: '/financial/installments/:id/pay', name: 'installment-pay', component: () => import('../pages/PaymentPage.vue'), meta: { requiresAuth: true } },
  { path: '/consent-records', name: 'consent-records', component: () => import('../pages/ConsentRecordsPage.vue'), meta: { requiresAuth: true } },
  { path: '/consent-records/:id', name: 'consent-record-sign', component: () => import('../pages/ConsentSignPage.vue'), meta: { requiresAuth: true } },
  { path: '/more',            name: 'more',            component: () => import('../pages/MorePage.vue'),         meta: { requiresAuth: true } },
  { path: '/notifications',   name: 'notifications',   component: () => import('../pages/NotificationsPage.vue'), meta: { requiresAuth: true } },
  { path: '/messages',        name: 'messages',        component: () => import('../pages/MessagesPage.vue'),     meta: { requiresAuth: true } },
  { path: '/profile',         name: 'profile',         component: () => import('../pages/ProfilePage.vue'),      meta: { requiresAuth: true } },

  // ─── Fallback ─────────────────────────────────────────────────────
  { path: '/:pathMatch(.*)*', redirect: { name: 'home' } }
];

const router = createRouter({ history: createWebHistory('/'), routes });

// Guard global:
//   1. Hidrata sessão a partir do JWT em localStorage no boot.
//   2. Bloqueia rotas auth se não tiver JWT.
//   3. Bloqueia rotas auth se precisa aceitar termo LGPD (exceto /consent).
//   4. Manda usuário logado em /login direto pra home.
let hydrated = false;
router.beforeEach(async (to) => {
  const auth = useAuthStore();

  if (!hydrated) {
    await auth.hydrate();
    hydrated = true;
  }

  if (to.meta.requiresAuth && !auth.isAuthenticated) return { name: 'login' };

  // Termo bloqueante — qualquer rota autenticada (exceto a própria /consent)
  // redireciona pra /consent enquanto o paciente não aceitar.
  if (auth.isAuthenticated && auth.needsPortalConsent && !to.meta.skipConsentGate) {
    return { name: 'consent' };
  }
  // Se já aceitou e tentou ir em /consent, manda pra home
  if (to.name === 'consent' && !auth.needsPortalConsent) return { name: 'home' };

  if (to.name === 'login' && auth.isAuthenticated) return { name: 'home' };
});

export default router;
