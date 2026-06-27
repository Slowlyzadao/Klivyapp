// Composable que encapsula "reportar joined/left pra automação de status"
// (Sprint K).
//
// Por que composable e não chamada inline no TelemedicineRoom:
//   - O componente da sala é PURO (não conhece API, roteamento, etc).
//     O wrapper (TelemedicineRoomPage / AgendaTelemedRoomPage) é quem fala
//     com o backend.
//   - Wrappers paciente e doutor têm clients de API diferentes mas a lógica
//     de idempotência + ordering é idêntica. Este composable é o ponto
//     único.
//
// Garantias:
//   1. `reportJoined` só dispara UMA vez por sessão (guard interno). UI
//      pode chamar 2x (mount + reconnect) — só vai a 1 request.
//   2. `reportLeft` mesmo padrão — se o usuário clicar Sair, Disconnected
//      do servidor também dispara, mas só 1 request sobe.
//   3. Erros NÃO propagam (sala não deve travar por causa de status). Log
//      e segue.
//   4. `reset()` re-arma os guards (uso: troca de token = nova sessão).
//
// Uso:
//   const { reportJoined, reportLeft, reset } = useTelemedicineSession({
//     reporter: (eventId, kind) => telemedicineApi.reportEvent(eventId, kind),
//     eventId: route.params.id
//   });
//
//   onMounted(reportJoined);
//   onBeforeUnmount(reportLeft);

/* eslint-disable no-console */
// no-console disable: reportar falhas é útil em dev/debug; não afeta UX (já
// engolimos o erro pra não travar a sala).

export function useTelemedicineSession({ reporter, eventId }) {
  let joinedReported = false;
  let leftReported = false;

  // Sprint L — opts.consented sinaliza ao backend que o paciente aceitou
  // o termo de gravação no preflight. Backend persiste em PatientPortalConsent
  // + custom_attributes.telemedicine_recording_consent_at no AgendaEvent
  // (orchestrator lê esse jsonb quando avalia se deve iniciar a gravação).
  async function reportJoined(opts = {}) {
    if (joinedReported || !eventId || !reporter) return;
    joinedReported = true;
    try {
      await reporter(eventId, 'joined', opts);
    } catch (err) {
      console.warn('[telemed-session] reportJoined falhou:', err);
    }
  }

  async function reportLeft() {
    if (leftReported || !eventId || !reporter) return;
    leftReported = true;
    try {
      await reporter(eventId, 'left');
    } catch (err) {
      console.warn('[telemed-session] reportLeft falhou:', err);
    }
  }

  function reset() {
    joinedReported = false;
    leftReported = false;
  }

  return { reportJoined, reportLeft, reset };
}
