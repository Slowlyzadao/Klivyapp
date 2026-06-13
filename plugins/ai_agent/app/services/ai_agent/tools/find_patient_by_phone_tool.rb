# Procura Patients da clínica que tenham o mesmo telefone do Contact
# ativo na conversa. Use ANTES de pedir nome ao paciente — se já existe
# cadastro com esse número, a Bea apenas reconhece, em vez de criar
# duplicata ou transferir.
#
# Estratégia de match: comparação dos ÚLTIMOS 8 DÍGITOS numéricos.
# No Brasil o número líquido (sem DDI, sem DDD, sem o 9 obrigatório
# do celular pós-2014) tem 8 dígitos. Suffix-match em 8 cobre TODOS
# os formatos coexistentes no banco — celular novo (11 dígitos),
# celular antigo sem 9 (10 dígitos), fixo (10 dígitos com DDD ou 8
# sem DDD), e com/sem +55 e máscara — sem perder match quando
# paciente cadastrado em formato A está conversando em formato B.
#
# MESMO NÚMERO = MESMA PESSOA: um cadastro achado pelo telefone é o
# próprio paciente, mesmo que esteja preso a um Contact antigo/duplicado
# (o WhatsApp recria o Contact de vez em quando). Nesses casos a tool
# RELIGA o paciente ao Contact atual (auto-cura) e segue reconhecendo —
# NUNCA trata como "vinculado a outro contato" nem transfere por isso.
class AiAgent::Tools::FindPatientByPhoneTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Busca pacientes da clínica que têm o mesmo telefone do paciente que
    está nesta conversa (telefone do Contact do WhatsApp). Use SEMPRE
    antes de iniciar agendamento, pra descobrir se o paciente já tem
    ficha cadastrada antes de pedir nome ou criar novo cadastro.

    Retornos possíveis:
      - { found: false } → ninguém com esse telefone, pergunte o nome
        completo e chame create_patient_minimal.
      - { found: true, already_linked: true, candidates: [...] } → o
        paciente JÁ TEM cadastro (mesmo número = mesma pessoa, mesmo que o
        Contact do WhatsApp tenha sido recriado). NÃO faça quiz de
        identidade e NÃO transfira: reconheça pelo primeiro nome e veja
        upcoming_appointments (ou chame list_appointments) antes de
        perguntar o motivo. Mais de um nome = família/dependentes:
        pergunte com leveza pra quem é o atendimento.
  DESC

  def execute
    return { found: false, reason: 'sem_contato' } if contact_id.blank?

    contact = ::Contact.find_by(id: contact_id, account_id: account.id)
    return { found: false, reason: 'contact_nao_encontrado' } if contact.nil?

    patients = recognized_patients(contact)
    return no_match_result(contact) if patients.empty?

    relink_to_contact!(patients, contact)
    candidates = patients.map { |p| candidate_hash(p) }
    appts = upcoming_appointment_events(limit: 5)
    {
      found: true,
      already_linked: true,
      contact_phone: contact.phone_number,
      candidates_count: candidates.size,
      candidates: candidates,
      upcoming_appointments: appts.map { |e| appointment_brief(e) },
      note_for_bea: recognized_note(candidates, appts)
    }
  end

  private

  # Patients ATIVOS do contato: por vínculo direto (contact_id) OU pelo
  # telefone (mesmo número = mesma pessoa, ainda que o Contact tenha sido
  # recriado). É o suffix-match de 8 dígitos descrito no topo da classe.
  def recognized_patients(contact)
    return [] unless defined?(::Patient)

    digits = contact.phone_number.to_s.gsub(/\D/, '')
    suffix = digits.length >= 8 ? digits.last(8) : digits
    rel = ::Patient.active.where(account_id: account.id)
    rel = if suffix.present?
            rel.where("contact_id = ? OR REGEXP_REPLACE(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", contact.id, "%#{suffix}")
          else
            rel.where(contact_id: contact.id)
          end
    rel.order(:name).to_a
  end

  # Auto-cura: religa ao Contact ATUAL os pacientes que estavam soltos ou
  # presos a um contato antigo/duplicado do mesmo número. Evita o falso
  # "vinculado a outro contato" quando o WhatsApp recria o Contact.
  def relink_to_contact!(patients, contact)
    stale = patients.reject { |p| p.contact_id == contact.id }
    return if stale.empty?

    ::Patient.where(id: stale.map(&:id)).update_all(contact_id: contact.id, updated_at: Time.current)
    stale.each { |p| p.contact_id = contact.id }
  end

  def candidate_hash(patient)
    {
      id: patient.id,
      name: patient.try(:full_name) || patient.name,
      status: patient.patient_status,
      already_linked_to_this_contact: true,
      last_appointment_date: last_appointment_date_for(patient)
    }
  end

  def no_match_result(contact)
    {
      found: false,
      contact_phone: contact.phone_number,
      note_for_bea: 'Nenhum paciente cadastrado com esse telefone. Peça o nome completo do paciente e use create_patient_minimal pra criar a ficha.'
    }
  end

  # Nota pra Bea: o paciente é reconhecido (mesmo número). >1 nome =
  # família/dependentes no mesmo WhatsApp.
  def recognized_note(candidates, appts)
    base = if candidates.size > 1
             names = candidates.pluck(:name).join(', ')
             "Paciente JÁ IDENTIFICADO + dependente(s) no mesmo WhatsApp: #{names}. " \
               'NÃO faça quiz de identidade e NÃO transfira. Reconheça com ' \
               'naturalidade e, ao agendar/consultar, pergunte com leveza se é ' \
               'pro titular ou pra um dependente — use o patient_id da pessoa certa.'
           else
             first = candidates.first
             "Paciente JÁ IDENTIFICADO — é #{first[:name]} (id #{first[:id]}). " \
               "NÃO faça quiz de identidade — NÃO pergunte \"você é fulano?\" nem peça " \
               'nome de novo, e NÃO transfira: é a mesma pessoa (mesmo número). ' \
               'Reconheça com calor pelo primeiro nome.'
           end
    "#{base} #{appointments_hint(appts)}"
  end

  # Resumo dos próximos agendamentos pra Bea citar logo na abertura — é o
  # que garante que ela reconheça a consulta marcada mesmo sem chamar
  # list_appointments num segundo passo.
  def appointments_hint(appts)
    if appts.blank?
      return 'O paciente NÃO tem consulta futura marcada: abra reconhecendo o ' \
             'cadastro e pergunte o motivo do contato de forma aberta e calorosa.'
    end

    list = appts.map { |e| appt_label(e) }.join('; ')
    if appts.size == 1
      "ATENÇÃO: o paciente tem 1 consulta marcada (#{list}). MENCIONE-a logo na " \
        'saudação de abertura (dia, horário e profissional) e pergunte se o ' \
        'contato é sobre ela.'
    else
      "ATENÇÃO: o paciente tem #{appts.size} consultas marcadas (#{list}). Logo na " \
        "abertura diga que viu as #{appts.size} consultas (cite cada uma por dia/horário) e " \
        'pergunte se o contato é sobre ALGUMA delas. Use o número EXATO; nunca invente.'
    end
  end

  def appt_label(event)
    quando = event.starts_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m às %H:%M')
    quem = event.user&.name
    pac = (event.custom_attributes || {})['patient_name']
    label = quem ? "#{quando} com #{quem}" : quando
    pac.present? ? "#{label} (paciente: #{pac})" : label
  end

  def appointment_brief(event)
    attrs = event.custom_attributes || {}
    {
      id: event.id,
      starts_at: event.starts_at.iso8601,
      professional: event.user&.name,
      patient_id: attrs['patient_id'],
      patient_name: attrs['patient_name']
    }
  end

  def last_appointment_date_for(patient)
    return nil unless defined?(::AgendaEvent)

    last = ::AgendaEvent.kept.where(account_id: account.id, contact_id: patient.contact_id)
                        .where.not(status: %w[cancelled no_show pending_confirmation])
                        .where('starts_at <= ?', Time.current)
                        .order(starts_at: :desc)
                        .limit(1)
                        .pick(:starts_at)
    last&.strftime('%d/%m/%Y')
  end
end
