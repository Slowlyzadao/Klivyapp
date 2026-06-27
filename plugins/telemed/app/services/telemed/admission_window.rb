# Decide se uma admissão server-side de paciente AINDA VALE.
#
# Bug 2026-05-22 — antes a admissão persistia indefinidamente em
# `event.custom_attributes['telemed_session']['admissions']`, então o
# paciente entrava sem precisar ser readmitido mesmo num evento que
# já acabou (caso real: sessão de teste de manhã deixou admit gravada,
# à tarde o paciente entrou direto sem o dentista poder aceitar). Agora
# admissão segue a JANELA DO EVENTO agendado:
#
#   - Reconexão durante a consulta (queda de wifi/4G)        → admit reusado ✅
#   - Paciente fora 5/10/15min e volta ainda dentro da janela → admit reusado ✅
#   - Próxima consulta do mesmo paciente (outro event_id)    → admit NÃO vale ✅
#   - Evento marcado completed/cancelled/no_show             → admit NÃO vale ✅
#   - Evento esquecido aberto fora da janela                 → admit NÃO vale ✅
#
# Reuso ESTRITO da fonte da verdade: a janela vem inteira de
# `Telemed::Session#in_admission_window?`, que usa o setting da clínica
# `telemedicine_pre_minutes` / `telemedicine_post_minutes`. Se um dia
# alguém ampliar a janela de entrada da sala, a janela de admit
# acompanha automaticamente — não há números hardcoded aqui.
#
# Por que NÃO usamos webhook `room_finished` do LiveKit pra limpar:
# o `empty_timeout` default é 5 min, então uma queda de wifi de 6 min
# já forçaria readmit (UX terrível em telemed real). Janela do evento
# desacopla a admissão da existência efêmera da sala.
module Telemed
  class AdmissionWindow
    # Status em que o evento não aceita mais admissões — mesmo dentro
    # da janela de tempo. Refletem "esta consulta acabou": completed,
    # no_show, cancelled (via discarded?), ou status final via UI.
    FINAL_STATUSES = %w[completed cancelled no_show].freeze

    def initialize(event:)
      @event = event
    end

    # Verdadeiro se o paciente já foi admitido E a admissão ainda é
    # válida agora. Usado em duas chamadas paralelas (admin + patient
    # portal) que precisam concordar — daí o helper compartilhado.
    def admitted?(patient_id:, now: Time.current)
      return false if patient_id.blank?
      return false if event_in_final_status?
      return false unless raw_admissions.key?(patient_id.to_s)
      Telemed::Session.new(event: @event).in_admission_window?(at: now)
    end

    # Filtra o hash inteiro mantendo só admissões ainda válidas. Usado
    # pela resposta do controller admin pra reidratar UI do dentista
    # sem mostrar pacientes fantasma de consultas passadas.
    def valid_admissions(now: Time.current)
      return {} if event_in_final_status?
      return {} unless Telemed::Session.new(event: @event).in_admission_window?(at: now)
      raw_admissions.select { |_pid, rec| rec.is_a?(Hash) && rec['admitted_at'].present? }
    end

    # Limpa TODAS as admissões do evento. Chamado pelo StatusTransition
    # quando o evento entra em status final — economiza JSON e elimina
    # qualquer chance de leak entre consultas distintas reusarem o
    # mesmo agenda_event_id (não acontece hoje, mas é defesa em
    # profundidade). `update_columns` pra não disparar callbacks.
    def self.clear_for!(event)
      return unless event
      attrs = event.custom_attributes || {}
      ts    = attrs['telemed_session']
      return unless ts.is_a?(Hash) && ts['admissions'].is_a?(Hash) && ts['admissions'].any?
      ts['admissions'] = {}
      attrs['telemed_session'] = ts
      event.update_columns(custom_attributes: attrs)
    end

    private

    def raw_admissions
      @event.custom_attributes&.dig('telemed_session', 'admissions') || {}
    end

    def event_in_final_status?
      return true if @event.try(:discarded?)
      FINAL_STATUSES.include?(@event.status.to_s)
    end
  end
end
