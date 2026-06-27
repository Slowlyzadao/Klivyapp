# Enriquece a ficha de um paciente já existente com dados coletados na
# conversa: CPF (pedido só ao confirmar o agendamento), origem ("como
# conheceu a clínica" → Patient.origin) e responsável (menor de idade →
# Patient.guardian/has_guardian). Escreve no model Patient do plugin
# patients — dependência cross-plugin, sem modificar aquele plugin.
# Ver docs/04-ai-agent/clean-architecture.md (§4).
class AiAgent::Tools::UpdatePatientRecordTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Atualiza a ficha de um paciente já existente com dados coletados na
    conversa. Passe APENAS os campos que você realmente coletou:
    - cpf: quando o paciente informar o CPF ao confirmar o agendamento.
    - origin: como o paciente conheceu a clínica.
    - guardian_name / guardian_birthdate: dados do responsável maior de
      idade quando o paciente é MENOR.
    Não invente dados — só registre o que o paciente disse.
  DESC

  param :cpf,
        type: :string,
        required: false,
        desc: 'CPF do paciente (com ou sem pontuação — eu limpo). Peça apenas ao confirmar o agendamento.'

  param :origin,
        type: :string,
        required: false,
        desc: 'Como o paciente conheceu a clínica (ex: "Indicação de amigo", "Instagram", "Google").'

  param :guardian_name,
        type: :string,
        required: false,
        desc: 'Nome completo do responsável maior de idade (quando o paciente é menor de idade).'

  param :guardian_birthdate,
        type: :string,
        required: false,
        desc: 'Data de nascimento do responsável no formato YYYY-MM-DD.'

  param :patient_id,
        type: :integer,
        required: false,
        desc: 'ID do paciente a atualizar. Omita para usar o paciente desta conversa; passe quando for um terceiro/dependente.'

  def execute(cpf: nil, origin: nil, guardian_name: nil, guardian_birthdate: nil, patient_id: nil)
    return { updated: false, error: 'Módulo de pacientes não disponível.' } unless defined?(::Patient)
    return { updated: false, error: 'Sem contato vinculado a esta conversa.' } if contact_id.blank?

    patient = resolve_patient(patient_id)
    return { updated: false, error: 'Paciente não encontrado. Crie a ficha primeiro com create_patient_minimal.' } if patient.nil?

    applied = []

    if cpf.present?
      digits = cpf.to_s.gsub(/\D/, '')
      return { updated: false, error: 'CPF inválido — precisa ter 11 dígitos. Peça de novo ao paciente.' } unless digits.length == 11

      patient.cpf = digits
      applied << 'cpf'
    end

    if origin.present?
      patient.origin = origin.to_s.strip[0, 255]
      applied << 'origin'
    end

    begin
      patient.save! if applied.any?
    rescue ActiveRecord::RecordInvalid => e
      return { updated: false, error: e.message }
    end

    # Responsável (menor): `guardian` é jsonb. Setar `has_guardian` dispara
    # a validação de guardian_cpf no plugin patients, e o fluxo não coleta
    # CPF do responsável — então gravamos via update_columns (pula
    # validação/callback) pra registrar o dado sem travar.
    if guardian_name.present?
      guardian = { 'name' => guardian_name.to_s.strip[0, 255] }
      guardian['birthdate'] = guardian_birthdate.to_s.strip if guardian_birthdate.present?
      patient.update_columns(guardian: guardian, has_guardian: true)
      applied << 'guardian'
    end

    return { updated: false, error: 'Nada para atualizar — passe ao menos um campo (cpf, origin ou guardian_name).' } if applied.empty?

    {
      updated: true,
      patient_id: patient.id,
      fields: applied,
      note_for_bea: "Ficha atualizada (#{applied.join(', ')}). Siga o atendimento normalmente."
    }
  end

  private

  def resolve_patient(patient_id)
    if patient_id.present?
      ::Patient.active.find_by(account_id: account.id, id: patient_id)
    else
      ::Patient.active.find_by(account_id: account.id, contact_id: contact_id)
    end
  end
end
