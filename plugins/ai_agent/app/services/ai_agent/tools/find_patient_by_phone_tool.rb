module AiAgent
  module Tools
    # Procura Patients da clínica que tenham o mesmo telefone do Contact
    # ativo na conversa. Use ANTES de pedir nome ao paciente — se já existe
    # cadastro vinculado a esse número, a Bea apenas confirma o nome em vez
    # de criar duplicata.
    #
    # Estratégia de match: comparação dos ÚLTIMOS 8 DÍGITOS numéricos.
    # No Brasil o número líquido (sem DDI, sem DDD, sem o 9 obrigatório
    # do celular pós-2014) tem 8 dígitos. Suffix-match em 8 cobre TODOS
    # os formatos coexistentes no banco — celular novo (11 dígitos),
    # celular antigo sem 9 (10 dígitos), fixo (10 dígitos com DDD ou 8
    # sem DDD), e com/sem +55 e máscara — sem perder match quando
    # paciente cadastrado em formato A está conversando em formato B.
    #
    # Tradeoff: aceita falso positivo teórico de dois pacientes em DDDs
    # diferentes com 8 últimos dígitos iguais (raríssimo dentro de uma
    # clínica regional). A operação é reversível (humano valida o nome
    # antes de qualquer ação irreversível via confirm_patient_identity).
    class FindPatientByPhoneTool < BaseTool
      description <<~DESC
        Busca pacientes da clínica que têm o mesmo telefone do paciente que
        está nesta conversa (telefone do Contact do WhatsApp). Use SEMPRE
        antes de iniciar agendamento, pra descobrir se o paciente já tem
        ficha cadastrada antes de pedir nome ou criar novo cadastro.

        Retornos possíveis:
          - { found: false } → ninguém com esse telefone, pergunte o nome
            completo e chame create_patient_minimal.
          - { found: true, candidates: [{id, name, ...}] } com 1 candidato
            → confirme o nome com o paciente. Se confirmar, chame
            confirm_patient_identity. Se o nome não bater, chame
            transfer_to_human (recepção resolve o cadastro).
          - { found: true, candidates: [...] } com N>1 candidatos →
            pergunte qual da família é (lista nomes) e siga com
            confirm_patient_identity no escolhido.
      DESC

      def execute
        return { found: false, reason: 'sem_contato' } if contact_id.blank?

        contact = ::Contact.find_by(id: contact_id, account_id: account.id)
        return { found: false, reason: 'contact_nao_encontrado' } if contact.nil?

        # Curto-circuito: se já existe Patient vinculado a este Contact,
        # o paciente JÁ FOI identificado em algum momento (este turno
        # ou turno anterior). Não force a Bea a re-confirmar — só aponta
        # quem é e instrui pra seguir.
        already = ::Patient.active.find_by(account_id: account.id, contact_id: contact.id)
        if already
          return {
            found: true,
            already_linked: true,
            candidates_count: 1,
            candidates: [
              {
                id: already.id,
                name: already.try(:full_name) || already.name,
                status: already.patient_status,
                already_linked_to_this_contact: true,
                already_linked_to_other_contact: false,
                last_appointment_date: last_appointment_date_for(already)
              }
            ],
            note_for_bea: "Paciente JÁ IDENTIFICADO nesta conversa — é #{already.try(:full_name) || already.name} (id #{already.id}). NÃO pergunte 'você é fulano?' nem peça nome de novo. Continue direto pro Passo 1 do AGENDAMENTO (clinic_info)."
          }
        end

        digits = contact.phone_number.to_s.gsub(/\D/, '')
        return { found: false, reason: 'sem_telefone_no_contato' } if digits.empty?

        # 8 últimos dígitos = parte invariante do número brasileiro.
        # Cobre simultaneamente celular novo (11), celular antigo (10) e
        # fixo (10), com ou sem DDI/máscara — desde que o cadastro do
        # paciente tenha pelo menos os 8 dígitos finais corretos, ele é
        # encontrado, mesmo que o operador tenha digitado em formato
        # diferente do que o paciente usa no WhatsApp hoje.
        suffix = digits.length >= 8 ? digits.last(8) : digits

        scope = ::Patient.active.where(account_id: account.id)
        scope = scope.where(
          "REGEXP_REPLACE(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?",
          "%#{suffix}"
        )

        candidates = scope.order(:name).limit(10).map do |p|
          {
            id: p.id,
            name: p.try(:full_name) || p.name,
            status: p.patient_status,
            already_linked_to_this_contact: p.contact_id == contact.id,
            already_linked_to_other_contact: p.contact_id.present? && p.contact_id != contact.id,
            last_appointment_date: last_appointment_date_for(p)
          }
        end

        if candidates.empty?
          return {
            found: false,
            contact_phone: contact.phone_number,
            note_for_bea: 'Nenhum paciente cadastrado com esse telefone. Peça o nome completo do paciente e use create_patient_minimal pra criar a ficha.'
          }
        end

        {
          found: true,
          contact_phone: contact.phone_number,
          candidates_count: candidates.size,
          candidates: candidates,
          note_for_bea: candidates.size == 1 ?
            "Achei 1 paciente com esse telefone. Confirme o nome (\"você é #{candidates.first[:name]}?\"). Se sim, chame confirm_patient_identity. Se o paciente disser que NÃO é essa pessoa, chame transfer_to_human." :
            'Mais de uma pessoa cadastrada com esse telefone (família compartilhando WhatsApp). Liste os nomes e pergunte qual é o paciente desta conversa, depois chame confirm_patient_identity no escolhido.'
        }
      end

      private

      def last_appointment_date_for(patient)
        return nil unless defined?(::AgendaEvent)

        last = ::AgendaEvent.where(account_id: account.id, contact_id: patient.contact_id)
                            .where.not(status: %w[cancelled no_show pending_confirmation])
                            .where('starts_at <= ?', Time.current)
                            .order(starts_at: :desc)
                            .limit(1)
                            .pick(:starts_at)
        last&.strftime('%d/%m/%Y')
      end
    end
  end
end
