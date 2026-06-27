// Bootstrap do SPA do Portal do Paciente.
// Estrutura: arquitetura limpa — `main.js` apenas wire-up; toda regra de
// negócio fica em store/components/pages. Sem lógica aqui.
import { createApp } from 'vue';
import { createPinia } from 'pinia';

import App from './App.vue';
import router from './router';
import './styles/app.css';

const app = createApp(App);
app.use(createPinia());
app.use(router);
app.mount('#patient-portal-app');
