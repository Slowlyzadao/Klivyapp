module AiAgent
  module Tools
    # Cria uma ficha mínima de paciente quando find_patient_by_phone retornou
    # vazio. Vincula automaticamente o Patient ao Contact desta conversa e
    # ao telefone que o paciente está usando — recepção completa CPF, e-mail,
    # data de nascimento depois pelo prontuário.
    #
    # Decisão de produto (Leandro, 2026-05-07): Bea NÃO pede CPF/nascimento
    # via WhatsApp pra não burocratizar primeiro contato. Nome completo +
    # telefone do contact + contact_id é o suficiente pra agendar.
    class CreatePatientMinimalTool < BaseTool
      description <<~DESC
        Cria uma ficha nova de paciente com o mínimo de dados (nome
        completo + telefone do WhatsApp + vínculo com este Contact).

        Dois cenários:
        1. Paciente novo (find_patient_by_phone retornou found=false e o
           paciente te informou o nome completo dele): chame com `name`.
        2. Paciente terceiro (família WhatsApp — quem está conversando
           está agendando para outra pessoa, ex: pai pra filho): chame
           com `name` + `is_third_party=true`. Se for menor de idade,
           passe também `birthdate` (formato YYYY-MM-DD).

        NÃO peça CPF, e-mail ou endereço — recepção completa depois.
        Para o cenário 1 não peça nem data de nascimento. Para o 2
        (terceiro), peça data de nascimento APENAS se for menor de idade.
      DESC

      param :name,
            type: :string,
            desc: 'Nome completo do paciente, exatamente como ele te informou.'

      param :birthdate,
            type: :string,
            required: false,
            desc: 'Data de nascimento no formato YYYY-MM-DD. Pode ser passada quando o paciente terceiro é menor de idade. Ex: "2015-03-22".'

      param :is_third_party,
            type: :boolean,
            required: false,
            desc: 'Se true, indica que o paciente NÃO é a pessoa que está conversando (ex: pai agendando pra filho). Permite criar uma 2ª ficha vinculada ao mesmo Contact (família WhatsApp). Default false.'

      def execute(name:, birthdate: nil, is_third_party: false)
        return { created: false, error: 'Sem contato vinculado a esta conversa.' } if contact_id.blank?

        clean_name = name.to_s.strip
        return { created: false, error: 'Nome muito curto — peça o nome completo.' } if clean_name.length < 2

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

        patient = ::Patient.create!(
          account_id: account.id,
          contact_id: contact_id,
          name: clean_name[0, 255],
          phone: contact.phone_number.to_s,
          birthdate: parsed_birthdate,
          patient_status: 'novo'
        )

        is_minor = parsed_birthdate.present? && (Date.current.year - parsed_birthdate.year) < 18

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
    end
  end
end
