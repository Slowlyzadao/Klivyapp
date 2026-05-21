# Gera e parseia o "código da sala" (Sprint K — Telemedicina).
#
# Formato: `pppp-eeee-aaaa` (estilo Google Meet `tkt-vxoc-drv`).
#   - pppp = patient_id (4 dígitos zero-padded; expande se > 9999)
#   - eeee = agenda_event_id (idem; serve como middle único — IDs são globais)
#   - aaaa = account_id (idem; útil pra suporte filtrar por clínica)
#
# Por que esse formato:
#   - Curto o suficiente pra paciente ler pelo telefone se precisar de suporte
#   - Carrega contexto suficiente pra log/auditoria sem expor PII
#   - Mantém a sala identificável mesmo se URL mudar de domínio
#
# Service idempotente, sem side effects.
module Telemed
  class RoomCode
    SEPARATOR = '-'.freeze
    MIN_PAD   = 4

    # Constrói o slug a partir de um AgendaEvent. `patient` é opcional —
    # se ausente, tenta resolver via event.contact.patient (caminho padrão
    # do plugin agenda). Retorna nil se faltar info essencial (event).
    def self.from_event(event, patient: nil)
      return nil unless event

      patient_id = resolve_patient_id(patient) || resolve_patient_id_from_event(event)
      [
        format_segment(patient_id),
        format_segment(event.id),
        format_segment(event.account_id)
      ].join(SEPARATOR)
    end

    # Parses 'pppp-eeee-aaaa' em {patient_id, event_id, account_id}.
    # Retorna nil se o slug for malformado — controllers checam antes de
    # tentar resolver no banco. Aceita zero-padding ou números maiores.
    def self.parse(slug)
      return nil unless slug.is_a?(String)

      parts = slug.split(SEPARATOR)
      return nil unless parts.length == 3
      return nil unless parts.all? { |p| p.match?(/\A\d+\z/) }

      {
        patient_id: parts[0].to_i,
        event_id:   parts[1].to_i,
        account_id: parts[2].to_i
      }
    end

    # `AgendaEvent.find('17-foo')` no Rails faz `to_i` → pega só o '17'
    # (perigoso, pode abrir evento errado). Use isso pra rotear ANTES de
    # chamar `.find`: se for slug, extraia o event_id via `parse`.
    def self.slug?(value)
      value.is_a?(String) && value.include?(SEPARATOR)
    end

    def self.resolve_patient_id(patient)
      return patient if patient.is_a?(Integer)
      return patient.id if patient.respond_to?(:id)

      nil
    end
    private_class_method :resolve_patient_id

    def self.resolve_patient_id_from_event(event)
      event.try(:patient)&.id ||
        event.try(:contact)&.try(:patient)&.id
    end
    private_class_method :resolve_patient_id_from_event

    def self.format_segment(id)
      return '0000' if id.nil? || id.to_i <= 0

      id.to_s.rjust(MIN_PAD, '0')
    end
    private_class_method :format_segment
  end
end
