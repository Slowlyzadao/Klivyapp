# Busca paciente por nome OU telefone — pra Pipeline B (Bea responde no
# Chat Interno). Diferente de PatientLookupTool/FindPatientByPhoneTool,
# esta NÃO depende de `contact_id` da sessão (no chat interno não há
# paciente específico vinculado à sala).
#
# Retorna até 5 matches. Equipe usa pra perguntas tipo "@bea Maria Silva
# já passou aqui antes?" ou "@bea esse 47 99999-1234 é da clínica?".
class AiAgent::Tools::InternalSearchPatientTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Busca paciente por nome ou telefone no prontuário da clínica. Use
    quando alguém da equipe perguntar sobre um paciente específico no
    chat interno. Retorna até 5 pacientes que casam com a busca.
  DESC

  param :query,
        type: :string,
        desc: 'Nome (ou parte do nome) ou telefone do paciente. Mínimo 2 caracteres. Ex: "Maria", "Silva", "47999991234".'

  def execute(query:)
    return { found: false, message: 'Busca muito curta (mínimo 2 caracteres).' } if query.to_s.strip.length < 2
    return { found: false, message: 'Módulo de pacientes não disponível.' } unless defined?(::Patient)

    # SEC-12: exige `patients:view`. Sem essa perm o staff não pode
    # nem visualizar lista de pacientes via UI — Bea não pode bypass.
    unless invoking_user_can?(:patients, :view)
      return {
        found: false,
        permission_denied: true,
        note_for_bea: 'Quem mencionou você não tem permissão pra consultar pacientes. ' \
                      'Avise educadamente que essa busca é restrita a quem tem acesso ao prontuário.'
      }
    end

    scope = ::Patient.active.where(account_id: account.id)
    digits = query.to_s.gsub(/\D/, '')

    results = if digits.length >= 4
                scope.where('phone LIKE ?', "%#{digits}%").limit(5)
              else
                scope.where('LOWER(name) LIKE ?', "%#{query.to_s.downcase}%").limit(5)
              end

    return { found: false, query: query, message: "Nenhum paciente encontrado pra '#{query}'." } if results.empty?

    {
      found: true,
      count: results.size,
      patients: results.map do |p|
        {
          id: p.id,
          name: p.try(:full_name).presence || p.name,
          phone: p.phone,
          status: p.patient_status,
          responsible_professional: p.try(:responsible_professional)&.name
        }
      end
    }
  end
end
