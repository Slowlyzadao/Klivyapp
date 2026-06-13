# Cria uma ficha mínima de paciente quando find_patient_by_phone retornou
# vazio. Vincula automaticamente o Patient ao Contact desta conversa e
# ao telefone que o paciente está usando — recepção completa e-mail,
# endereço e demais dados depois pelo prontuário.
#
# Decisão de produto (Leandro, 2026-06-06, revoga a de 2026-05-07): o
# mínimo da ficha é NOME COMPLETO + CPF (BIA.md passo 2.6). Bea pede os
# dois antes de agendar. Exceção: dependente menor de idade pode entrar
# só com nome + data de nascimento (CPF do menor é opcional — o
# responsável regulariza na clínica).
class AiAgent::Tools::CreatePatientMinimalTool < AiAgent::Tools::BaseTool
  # SEC-14 (auditoria 2026-05-18): paciente pode pedir "cria ficha pra
  # X, Y, Z..." em rajada no WhatsApp e Bea vai criando Patient órfãos.
  # Cobertura legítima é família (pai + filho + cônjuge) = ~3-5 fichas
  # por contact ao longo do tempo. 5/dia é largo o suficiente pra
  # cobrir caso real e cortar abuso. Chave Redis com TTL de 24h.
  DAILY_LIMIT_PER_CONTACT = 5
  RATE_LIMIT_TTL = 24.hours

  description <<~DESC
    Cria uma ficha nova de paciente com o mínimo de dados (nome
    completo + telefone do WhatsApp + vínculo com este Contact).

    Dois cenários:
    1. Paciente novo (find_patient_by_phone retornou found=false e o
       paciente te informou o nome completo dele): chame com `name`
       + `cpf` (ambos obrigatórios).
    2. Paciente terceiro (família WhatsApp — quem está conversando
       está agendando para outra pessoa, ex: pai pra filho): chame
       com `name` + `cpf` + `is_third_party=true`. Se for menor de
       idade, passe também `birthdate` (formato YYYY-MM-DD) — nesse
       caso o `cpf` do menor é opcional.

    SEMPRE peça nome completo E CPF antes de criar a ficha (mínimo do
    cadastro). NÃO peça e-mail ou endereço — a recepção completa depois.
    Para o cenário 2 (terceiro), peça data de nascimento APENAS se for
    menor de idade.
  DESC

  param :name,
        type: :string,
        desc: 'Nome completo do paciente, exatamente como ele te informou.'

  param :cpf,
        type: :string,
        required: false,
        desc: 'CPF do paciente (obrigatório, exceto dependente menor). Aceita com ou sem pontuação, ex: "123.456.789-09".'

  param :birthdate,
        type: :string,
        required: false,
        desc: 'Data de nascimento no formato YYYY-MM-DD. Pode ser passada quando o paciente terceiro é menor de idade. Ex: "2015-03-22".'

  param :is_third_party,
        type: :boolean,
        required: false,
        desc: 'Se true, indica que o paciente NÃO é a pessoa que está conversando (ex: pai agendando pra filho). Permite criar uma 2ª ficha vinculada ao mesmo Contact (família WhatsApp). Default false.'

  def execute(name:, cpf: nil, birthdate: nil, is_third_party: false)
    return { created: false, error: 'Sem contato vinculado a esta conversa.' } if contact_id.blank?

    # SEC-14: hard cap por contact por dia. Mensagem é educada e não
    # vazia detalhes do limiter (LLM não precisa saber, paciente menos
    # ainda — abuse vector evidenciado).
    if rate_limit_exceeded?
      Rails.logger.warn("[AiAgent::CreatePatientMinimalTool] rate limit hit account=#{account.id} contact=#{contact_id}")
      return {
        created: false,
        rate_limited: true,
        note_for_bea: 'Atingiu o limite diário de criação de fichas por este contato. ' \
                      'Avise o paciente que vou chamar alguém da equipe pra ajudar e disparar transfer_to_human.'
      }
    end

    clean_name = name.to_s.strip
    return { created: false, error: 'Nome muito curto — peça o nome completo.' } if clean_name.length < 2

    # Nome COMPLETO digitado pelo paciente — recusa push-name do WhatsApp.
    # Caso real: paciente mandou só o CPF e o LLM preencheu name com o nome
    # do contato ("Leandro L", de "Leandro L | Benuv") → ficha com nome lixo.
    unless full_name_plausible?(clean_name)
      return { created: false, invalid_name: true,
               note_for_bea: "\"#{clean_name}\" não parece um NOME COMPLETO de pessoa. É PROIBIDO preencher name com o " \
                             'nome do contato do WhatsApp: pergunte ao paciente o nome completo (nome + sobrenome) e ' \
                             'chame de novo com o que ele DIGITAR na conversa.' }
    end

    contact = ::Contact.find_by(id: contact_id, account_id: account.id)
    return { created: false, error: 'Contact não encontrado.' } if contact.nil?

    # Bloqueia duplicata APENAS quando NÃO é família — fluxo padrão
    # (paciente da própria conversa) ainda devolve o existente. No
    # cenário "pai agenda pra filho" liberamos a criação de 2ª ficha.
    #
    # Defesa: o LLM esquece o flag `is_third_party=true` em conversas
    # longas. Quando o nome passado não bate com nenhum Patient ativo
    # neste Contact (família — "Gabriel" enquanto cadastro é "Leandro"),
    # AUTO-detecta como terceiro mesmo sem o flag. Sem isso, o tool
    # devolveria "already_existed" do Leandro e o evento ia pra pessoa
    # errada.
    unless is_third_party
      existing_list = ::Patient.active
                               .where(account_id: account.id, contact_id: contact_id)
                               .pluck(:name)
      existing_match = existing_list.find { |n| names_match?(n, clean_name) }

      if existing_match
        existing = ::Patient.active.find_by(account_id: account.id, contact_id: contact_id, name: existing_match)
        return {
          created: false,
          already_existed: true,
          patient: { id: existing.id, name: existing.try(:full_name) || existing.name },
          note_for_bea: 'Paciente já tinha ficha vinculada a este Contact. Siga pro agendamento normalmente.'
        }
      end

      # Nome diferente de todo cadastro existente neste Contact = família.
      # Promove pra is_third_party automaticamente.
      if existing_list.any?
        Rails.logger.info("[CreatePatientMinimal] auto-promoted is_third_party=true: nome \"#{clean_name}\" não bate com #{existing_list.inspect}")
        is_third_party = true
      end
    end

    parsed_birthdate = parse_birthdate(birthdate)
    return { created: false, error: "Data de nascimento inválida: #{birthdate}" } if birthdate.present? && parsed_birthdate.nil?

    is_minor = parsed_birthdate.present? && (Date.current.year - parsed_birthdate.year) < 18

    # CPF obrigatório no cadastro (BIA.md passo 2.6). Única exceção:
    # dependente menor de idade — entra só com nome + nascimento, o
    # responsável regulariza o CPF na clínica. CPF guardado só com
    # dígitos (o Patient model também faz strip, mas normalizamos aqui
    # pra validar os 11 dígitos antes de bater no banco).
    clean_cpf = cpf.to_s.gsub(/\D/, '')
    cpf_required = !(is_third_party && is_minor)
    if cpf_required && clean_cpf.blank?
      return {
        created: false,
        missing_cpf: true,
        note_for_bea: 'Falta o CPF — peça o CPF do paciente (obrigatório pra criar a ficha) antes de chamar create_patient_minimal de novo.'
      }
    end
    return { created: false, error: "CPF inválido (#{cpf}). Peça os 11 dígitos do CPF de novo." } if clean_cpf.present? && clean_cpf.length != 11

    patient = ::Patient.create!(
      account_id: account.id,
      contact_id: contact_id,
      name: clean_name[0, 255],
      cpf: clean_cpf.presence,
      phone: contact.phone_number.to_s,
      birthdate: parsed_birthdate,
      patient_status: 'novo'
    )

    # SEC-14: incrementa contador APÓS criação bem-sucedida. Tentativas
    # com erro de validação (nome muito curto, data inválida) não contam,
    # então paciente legítimo não é punido por engano de digitação do LLM.
    bump_rate_counter!

    note = if is_third_party && is_minor
             "Ficha criada para \"#{patient.name}\" (menor de idade, vinculada ao WhatsApp do responsável). Lembre o paciente que precisa vir acompanhado e assinar o termo de responsabilidade do menor na clínica."
           elsif is_third_party
             "Ficha criada para \"#{patient.name}\" (terceiro vinculado ao WhatsApp). Pode seguir pro agendamento."
           else
             "Ficha criada com nome \"#{patient.name}\" e o telefone do WhatsApp. Pode seguir pro agendamento. Avise o paciente que a recepção completa o cadastro depois."
           end

    {
      created: true,
      patient: {
        id: patient.id,
        name: patient.name,
        status: patient.patient_status,
        is_minor: is_minor,
        is_third_party: is_third_party
      },
      note_for_bea: note
    }
  rescue ActiveRecord::RecordInvalid => e
    { created: false, error: e.message }
  end

  private

  # Nome completo plausível de PESSOA: sem símbolos de handle (| @ _ ou
  # dígitos, comuns em push-name de WhatsApp) e pelo menos 2 palavras
  # significativas (ignorando conectivos) com 2+ letras cada — mata
  # "Leandro L" (sobrenome truncado do contato), "Memama", "~".
  def full_name_plausible?(name)
    return false if name.match?(/[|@_\d~]/)

    significant = name.split(/\s+/).reject { |w| %w[de da do dos das e].include?(w.downcase) }
    significant.size >= 2 && significant.all? { |w| w.gsub(/[^[:alpha:]]/, '').length >= 2 }
  end

  # Compara nomes pra detectar família vs mesma pessoa. Match SE a
  # primeira palavra (primeiro nome, normalizada — sem acento, sem
  # pontuação, lowercase) bate. Tolerante a abreviações
  # ("Maria S. Silva" ≈ "Maria Silva"). Retorna false em divergência
  # do primeiro nome — é família WhatsApp.
  def names_match?(a, b)
    norm_a = normalize_first_name(a)
    norm_b = normalize_first_name(b)
    return false if norm_a.blank? || norm_b.blank?

    norm_a == norm_b
  end

  def normalize_first_name(s)
    first = s.to_s.strip.split(/\s+/).first.to_s
    # Remove acentos: NFD decomposition + drop combining marks
    first.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z]/, '')
  end

  def parse_birthdate(raw)
    return nil if raw.blank?

    Date.parse(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # SEC-14 — Redis counter por (account, contact, dia). Falha silenciosa
  # se Redis indisponível (não bloqueia criação legítima por incidente
  # de infra) — observabilidade fica no logger.warn.
  def rate_limit_exceeded?
    count = ::Redis::Alfred.get(rate_key).to_i
    count >= DAILY_LIMIT_PER_CONTACT
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::CreatePatientMinimalTool] redis check failed: #{e.class}: #{e.message}")
    false
  end

  def bump_rate_counter!
    count = ::Redis::Alfred.incr(rate_key)
    ::Redis::Alfred.expire(rate_key, RATE_LIMIT_TTL.to_i) if count == 1
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::CreatePatientMinimalTool] redis bump failed: #{e.class}: #{e.message}")
  end

  def rate_key
    "ai_agent:create_patient_minimal:#{account.id}:#{contact_id}:#{Date.current}"
  end
end
