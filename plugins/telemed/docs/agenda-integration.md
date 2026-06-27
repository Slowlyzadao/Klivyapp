# Agenda — Teleconsulta (Sprint K admin-side)

Doc de handoff para o programador que vai manter a feature de teleconsulta
no lado clínica (modal de agenda + popup de detalhes). Resume o que mudou,
por que mudou assim, onde tocar pra estender.

> **Sprint K do plano** já entregou o lado do paciente (botão "Entrar agora"
> no portal do paciente). Esta entrega completa o ciclo: a clínica pode
> **agendar** uma teleconsulta direto pelo modal da Agenda e o **profissional
> responsável** entra na mesma sala LiveKit pelo card do agendamento.

---

## Atualização 2026-05-19 — Google Meet pattern (sala de espera)

Antes: o backend recusava `telemedicine_token` fora da janela (10min antes /
30min depois) com 422. Agora:

- **Doutor entra a qualquer hora.** O botão "Entrar na sala" no popup da
  agenda fica sempre habilitado (a menos que consulta esteja cancelada /
  status final). Útil pra testar conexão, atrasar paciente, etc.
- **Paciente entra a qualquer hora também**, mas:
  - Se dentro da janela normal → conecta direto, publica mic/cam.
  - Se **fora** da janela → vê modal "Sua consulta começa em X min. Continuar?".
    Se confirmar, vai pra **sala de espera** (não publica tracks ainda).
  - Doutor vê **banner amarelo no topo da sala** com lista "X pacientes querem
    entrar" + botão **Admitir** por paciente. Quando admite, envia Data Channel
    direcionado (`destinationIdentities`) e o paciente passa a publicar mic/cam.

**Implementação:**

- `TelemedicineSession.rb`: novos `permanently_blocked?` (bloqueios fatais)
  e `outside_window?` (relaxável → sala de espera).
- Controllers (paciente + admin): trocam `can_join_now?` por
  `permanently_blocked?`. Sempre emitem token quando não está bloqueado
  permanentemente. Resposta inclui `outside_window`, `starts_in_seconds`
  no `data`.
- `TelemedicineRoom.vue`: ganhou props `role` ('doctor' | 'patient') e
  `requiresAdmit`. Paciente em waiting room usa `createLocalVideoTrack` /
  `createLocalAudioTrack` standalone (preview sem publicar). Recebe Data
  Channel `{type:'admit', target: identity}` → publica tracks.
- `TelemedicineJoinButton.vue`: removida checagem de janela — fica sempre
  habilitado se evento é teleconsulta e usuário é o profissional.

**Por que sala de espera client-side em vez de LiveKit permissions:**

LiveKit suporta token permissions (canPublish=false), mas mudar dinamicamente
exige chamar `RoomService.update_participant` server-side. Pra MVP, é mais
simples: paciente entra na sala mas **não cria/publica tracks** até receber
data channel. Doutor não vê o paciente até ele publicar. Bandwidth zero
gasto enquanto espera, sem ida-e-volta com o backend.

**Cenário do "doutor entrou primeiro":** quando o doutor conecta, ele itera
`room.remoteParticipants` no `connect()` e enfileira qualquer `patient-*`
como pendente. Funciona mesmo que paciente tenha entrado antes.

---

## TL;DR — O que mudou

1. **Modal "Nova consulta" ganhou a aba `Teleconsulta`**, ao lado de Consulta /
   Compromisso / Bloqueio. O form é **idêntico ao de Consulta** — a única
   diferença é que ao salvar marcamos `custom_attributes.telemedicine_enabled = true`.
2. **Popup de detalhes do agendamento ganhou o botão `Entrar na sala`** no
   footer, ao lado de "Editar" e "Prontuário". Só aparece pra teleconsultas
   E para o profissional responsável pelo horário.
3. **Backend** ganhou o endpoint `POST /api/v1/accounts/:account_id/agenda_events/:id/telemedicine_token`
   que emite um JWT LiveKit pro profissional com `role='doctor'`.
4. **Componente `TelemedicineRoom.vue`** foi extraído como peça pura
   reutilizável — a página do paciente e a página admin renderizam ambos.

Sem migração de banco: o flag mora em `agenda_events.custom_attributes` (JSONB).

---

## Decisão central: por que **não** criamos `event_type='telemedicine'`

Pensamos em adicionar um quarto `event_type` no schema, mas optamos por **manter
`event_type='consultation'` + flag JSONB** porque:

- **Uma teleconsulta É uma consulta**, só acontece por vídeo. Status flow,
  cobrança, recall, lembretes, métricas — tudo é igual.
- Reaproveita 100% da infra já testada do `PatientPortal::TelemedicineSession`
  (Sprint J) que já lê `custom_attributes.telemedicine_enabled`.
- O `AppointmentVisibility` do paciente já lista teleconsultas sem mudança.
- Reports que filtram por `event_type` continuam corretos.

Trade-off: a "aba Teleconsulta" no modal é **açúcar de UI** — não corresponde
a um valor no enum do banco. O modal mapeia internamente via `TAB_DEFS`.

---

## Backend

### Endpoint

```
POST /api/v1/accounts/:account_id/agenda_events/:id/telemedicine_token
```

- **Resposta 200**: `{ data: { url, token, room, identity, name, ttl_seconds, dev_mode } }`
- **Resposta 401**: Pundit barrou (não é o profissional responsável).
- **Resposta 422 `telemedicine_not_enabled`**: evento não tem o flag.
- **Resposta 422 `too_early` / `window_closed`**: fora da janela.
- **Resposta 500 `telemedicine_issue_failed`**: erro inesperado (LiveKit fora,
  credencial inválida, etc.).

### Onde está

| Camada      | Arquivo                                                                                    | Linhas-chave |
|-------------|--------------------------------------------------------------------------------------------|--------------|
| Rota        | `config/routes.rb`                                                                         | Bloco `resources :agenda_events do member do post :telemedicine_token` |
| Controller  | `plugins/agenda/app/controllers/api/v1/accounts/agenda_events_controller.rb`               | Action `telemedicine_token` |
| Policy      | `app/policies/agenda_event_policy.rb`                                                      | Método `telemedicine_join?` |
| Service     | (reusado) `plugins/patient_portal/app/services/patient_portal/telemedicine_session.rb`     | Cálculo da janela |
| Service     | (reusado) `plugins/patient_portal/app/services/patient_portal/telemedicine/session_issuer.rb` | Emissão do JWT, agora com `role='doctor'` |
| Specs       | `spec/controllers/api/v1/accounts/agenda_events_controller_spec.rb`                        | Bloco `describe 'POST .../telemedicine_token'` (6 cases) |
| Factory     | `spec/factories/agenda_events.rb`                                                          | Trait `:telemedicine` |

### Regra de autorização (importante)

```ruby
def telemedicine_join?
  return false unless beclinic_can?(:agenda, :view)
  record.user_id == user.id   # STRICT — só o responsável
end
```

**Mesmo Admin não passa se não for o dono do evento.** A identity da sala
LiveKit precisa ser o dentista real (paciente vê quem está atendendo). Se a
clínica quiser que outra pessoa cubra, precisa **reatribuir** o evento pra
ela antes (`user_id` no PATCH /agenda_events/:id).

### Reuso do SessionIssuer

O service `PatientPortal::Telemedicine::SessionIssuer` já aceita o parâmetro
`role:` desde a Sprint K. Aqui passamos `role: 'doctor'` e `participant: Current.user`.
A `identity` final fica `"doctor-#{user.id}"`, e o paciente fica
`"patient-#{patient.id}"` — identities distintas pro LiveKit tratar como
participants separados (importante pro PIP e active-speaker).

A `room` é determinística (`klivy-acc#{account_id}-event#{event_id}`) — paciente
e profissional caem na mesma sala.

---

## Frontend

### Mapa de arquivos

| Tipo               | Arquivo                                                                                           | Papel |
|--------------------|---------------------------------------------------------------------------------------------------|-------|
| Modal              | `plugins/agenda/frontend/components/AgendaEventModal.vue`                                         | 4ª aba `Teleconsulta` (reusa form de Consulta) |
| Modal helpers      | `plugins/agenda/frontend/utils/agenda-date.js`                                                    | `createDefaultNewEvent` agora aceita `telemedicine_enabled` |
| Save/edit          | `plugins/agenda/frontend/composables/useAgendaCrud.js`                                            | Serializa o flag no `custom_attributes` |
| Popup detalhes     | `plugins/agenda/frontend/components/AgendaEventInfoPopup.vue`                                     | Renderiza o botão "Entrar na sala" |
| **Botão**          | `plugins/agenda/frontend/components/TelemedicineJoinButton.vue`                                   | Componente reutilizável (oculta/disable conforme janela e role) |
| **Composable**     | `plugins/agenda/frontend/composables/useTelemedicineJoin.js`                                      | Pede token → guarda em sessionStorage → abre janela |
| API client         | `plugins/agenda/frontend/api/agendaTelemedicine.js`                                               | `issueToken(eventId)` |
| Página admin sala  | `plugins/agenda/frontend/routes/AgendaTelemedRoomPage.vue`                                        | Wrapper fino — lê token do sessionStorage e monta a sala |
| Rota               | `plugins/agenda/frontend/routes/routes.js`                                                        | `agenda_telemed_room` em `/agenda/telemed/:eventId` |
| **Sala pura**      | `plugins/patient_portal/frontend/components/TelemedicineRoom.vue`                                 | Componente puro reutilizado pelos dois lados (paciente + clínica) |
| Wrapper paciente   | `plugins/patient_portal/frontend/pages/TelemedicineRoomPage.vue`                                  | Wrapper fino do paciente |

### Fluxo do botão "Entrar na sala"

```
[dentista clica no card] → AgendaEventInfoPopup
                              │
                              ▼
                    <TelemedicineJoinButton />
                              │  (computeds)
                              ▼
   visible?  = telemedicine_enabled && user_id === current_user.id
   enabled? = janela aberta (10min antes a 30min depois, espelha backend)
                              │
                              ▼
                       useTelemedicineJoin.join(event)
                              │
                              ├── POST .../telemedicine_token
                              ├── sessionStorage.set('klivy:telemed:<id>', payload)
                              └── window.open('/agenda/telemed/:eventId')
                                              │
                                              ▼
                                  AgendaTelemedRoomPage.vue
                                              │
                                              ├── consumeToken(eventId)  ← one-shot do sessionStorage
                                              │   (ou reissue se vazio)
                                              ▼
                                  <TelemedicineRoom :url :token />
                                              │
                                              ▼
                                      LiveKit JS SDK
```

### Por que `sessionStorage` em vez de querystring

Token JWT é **credencial**. Não passa pela URL porque:
- vaza em cache de browser, histórico, logs de proxy/CDN, screenshots
- pode ser indexado se a aba for compartilhada por engano

`sessionStorage` é per-aba, some quando fecha, e o consumo é one-shot
(remove ao ler) — se a aba refresh, força reemissão (TTL é 10min).

### Por que o botão calcula janela client-side

Pra evitar um roundtrip por render do popup. **O backend continua sendo a
fonte da verdade** — se o cliente mostrar o botão por engano, o endpoint
`telemedicine_token` ainda recusa com `too_early`/`window_closed`.

### Permissions (frontend)

A rota `agenda_telemed_room` está em `meta.permissions` com os papéis padrão
da agenda. Quem não tem `agenda:view` nem chega no front. E quem chega mas
não é o responsável recebe 401 do backend.

---

## Como testar manualmente

1. **Subir o LiveKit dev**: `livekit-server --dev --bind 127.0.0.1` (já no
   `Procfile.dev`, vem com Foreman).
2. **Criar uma teleconsulta**:
   - Login como Admin / Dr Teste.
   - Agenda → "Nova consulta" → aba **Teleconsulta**.
   - Selecionar paciente, horário próximo agora (5 min).
   - Confirmar.
3. **Entrar na sala**:
   - Clicar no card do evento → popup abre.
   - Footer mostra `📹 Entrar na sala` em verde.
   - Clicar → abre nova aba com a sala LiveKit.
4. **Cenário negativo**:
   - Logar com outro dentista (Admin diferente, atribuído a outra agenda).
   - Card mostra os mesmos dados mas **sem botão "Entrar na sala"** (regra
     `record.user_id == user.id`).
5. **Cenário paciente**:
   - Em outra aba, abrir `pacientes.localhost:3000` como o paciente do
     agendamento.
   - Ir em "Consultas" → o card aparece com botão "Entrar agora".
   - Clicar → cai na MESMA sala que o dentista.

---

## Cenários futuros (próximas sprints)

- **Re-emitir token periodicamente** se a consulta passar de 10min. Hoje
  expira e cai a sala. Fácil: o composable pode rearmar e o componente
  reusar via `watch(props.token)` (já implementado).
- **Lembrete de teleconsulta** no recall/email do paciente — `custom_attributes.telemedicine_enabled`
  é o lugar canônico pra detectar.
- **Permitir gerente assistir** sem entrar como participant. Hoje a regra é
  strict; pra dar acesso "observer", criar `role='observer'` no SessionIssuer
  com `canPublish=false` e relaxar a policy condicionalmente.
- **Toolbar "iniciar atendimento"**: clicar em "Entrar na sala" também
  poderia mover o status do evento de `confirmed` → `in_progress`. Hoje o
  dentista faz isso manualmente. Inserir essa transição no
  `useTelemedicineJoin.join()` antes do `window.open`.
- **i18n**: as strings hardcoded em português (botão, banner do modal,
  página da sala) estão marcadas com `eslint-disable vue/no-bare-strings-in-template`.
  Quando o projeto for traduzido, ver `docs/03-engineering/` pro padrão.

---

## Smoke checklist antes de mergear novas mudanças

- [ ] Specs do controller passam: `bundle exec rspec spec/controllers/api/v1/accounts/agenda_events_controller_spec.rb -e "telemedicine_token"`
- [ ] Lint dos arquivos novos limpa: `pnpm exec eslint plugins/agenda/frontend/components/TelemedicineJoinButton.vue plugins/patient_portal/frontend/components/TelemedicineRoom.vue` (warnings de i18n aceitos)
- [ ] Manual: criar teleconsulta → editar abre na aba certa → save mantém o flag.
- [ ] Manual: trocar pra aba Consulta num evento já marcado como teleconsulta limpa o flag.
- [ ] Manual: paciente e dentista entram na mesma room.
