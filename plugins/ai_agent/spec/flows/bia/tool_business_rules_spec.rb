# Auditoria BIA.md — CAMADA DETERMINÍSTICA (FASE 1a).
#
# Cada exemplo aqui exercita uma REGRA DE NEGÓCIO das tools que a Bia usa,
# com DB real (sem mock do LLM). Os nomes dos exemplos carregam o ID do
# caso do BIA.md (T06, T08, T13…T23) pra rastreabilidade direta com a
# especificação. Esta camada não testa o roteamento do LLM (isso é
# conversation_routing_spec.rb) — testa que, QUANDO a tool é chamada, ela
# faz exatamente o que o fluxo exige.
require 'rails_helper'

RSpec.describe 'BIA.md — regras de negócio das tools (determinístico)' do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  # Contexto que toda tool recebe (account + contact + memória/estado).
  # patient_memory/conversation_state ficam nil — as tools usam `&.` e não
  # dependem deles pra regra de negócio.
  def ctx(contact_id: contact.id)
    AiAgent::ChatService::Context.new(
      account: account, conversation_state: nil, patient_memory: nil, contact_id: contact_id
    )
  end

  # Agenda mínima funcional: configuração de horários (Seg–Sáb), 1 serviço
  # e 1 profissional habilitado pra ele. Usada pelos casos de agenda.
  def setup_agenda!(duration: 60)
    AgendaSetting.create!(account: account)
    service = create(:agenda_service, account: account, duration_minutes: duration)
    professional = create(:user, account: account, role: :agent, name: 'Ana Paula Souza')
    AgendaServiceUser.create!(account_id: account.id, agenda_service: service, user: professional)
    [service, professional]
  end

  # Data inicial sempre uma semana à frente: garante que TODOS os slots do
  # dia são futuros (o allocator descarta horários passados), sem depender
  # da hora em que o spec roda.
  def from_next_week
    (Date.current + 7).iso8601
  end

  # ── T20 — CADASTRO: mínimo Nome completo + CPF ──────────────────────
  describe 'T20 — create_patient_minimal exige Nome completo + CPF' do
    subject(:tool) { AiAgent::Tools::CreatePatientMinimalTool.new(ctx) }

    it 'T20_cria_ficha_com_nome_e_cpf' do
      result = tool.execute(name: 'Mariana Souza Lima', cpf: '111.444.777-35')

      expect(result[:created]).to be(true)
      patient = Patient.find(result[:patient][:id])
      expect(patient.name).to eq('Mariana Souza Lima')
      expect(patient.cpf).to eq('11144477735') # guardado só com dígitos
      expect(patient.contact_id).to eq(contact.id) # atrelado ao telefone/contato
    end

    it 'T20_recusa_sem_cpf_e_pede_o_cpf' do
      result = tool.execute(name: 'Mariana Souza Lima')

      expect(result[:created]).to be(false)
      expect(result[:missing_cpf]).to be(true)
      expect(result[:note_for_bea]).to match(/CPF/i)
      expect(Patient.where(contact_id: contact.id)).to be_empty
    end

    it 'T20_recusa_cpf_invalido' do
      result = tool.execute(name: 'Mariana Souza Lima', cpf: '123')

      expect(result[:created]).to be(false)
      expect(result[:error]).to match(/CPF inv/i)
    end

    it 'T20_recusa_nome_muito_curto' do
      result = tool.execute(name: 'A', cpf: '11144477735')

      expect(result[:created]).to be(false)
      expect(result[:error]).to match(/nome/i)
    end

    # Regressão 2026-06-12: paciente mandou só o CPF e o LLM preencheu o
    # name com o push-name do contato ("Leandro L", de "Leandro L | Benuv")
    # → ficha criada com nome lixo. Nome tem que ser completo e digitado.
    it 'T20_recusa_push_name_do_whatsapp_como_nome' do
      ['Leandro L', 'Memama', 'Leandro L | Benuv', 'leo_123'].each do |fake|
        result = AiAgent::Tools::CreatePatientMinimalTool.new(ctx).execute(name: fake, cpf: '11144477735')

        expect(result[:created]).to be(false), "esperava recusar #{fake.inspect}"
        expect(result[:invalid_name]).to be(true), "esperava invalid_name pra #{fake.inspect}"
        expect(result[:note_for_bea]).to match(/nome completo/i)
      end
      expect(Patient.where(contact_id: contact.id)).to be_empty
    end

    it 'T20_aceita_nome_completo_com_conectivo' do
      result = tool.execute(name: 'Maria de Souza', cpf: '11144477735')

      expect(result[:created]).to be(true)
    end
  end

  # ── T23 — DEPENDENTE menor: nome + nascimento; CPF opcional ─────────
  describe 'T23 — dependente menor de idade' do
    subject(:tool) { AiAgent::Tools::CreatePatientMinimalTool.new(ctx) }

    it 'T23_menor_terceiro_entra_sem_cpf_com_nascimento' do
      result = tool.execute(name: 'Pedro Gomes Silva', birthdate: '2018-03-12', is_third_party: true)

      expect(result[:created]).to be(true)
      expect(result[:patient][:is_minor]).to be(true)
      expect(result[:patient][:is_third_party]).to be(true)
      patient = Patient.find(result[:patient][:id])
      expect(patient.birthdate.to_s).to eq('2018-03-12')
      expect(patient.contact_id).to eq(contact.id) # vinculado ao WhatsApp do responsável
    end

    it 'T23_adulto_terceiro_ainda_exige_cpf' do
      result = tool.execute(name: 'Patricia Gomes Silva', birthdate: '1990-05-10', is_third_party: true)

      expect(result[:created]).to be(false)
      expect(result[:missing_cpf]).to be(true)
    end

    it 'T23_segunda_ficha_no_mesmo_contato_eh_familia' do
      tool.execute(name: 'Patricia Gomes Silva', cpf: '39053344705')
      result = AiAgent::Tools::CreatePatientMinimalTool.new(ctx)
                                                       .execute(name: 'Pedro Gomes Silva', birthdate: '2018-03-12', is_third_party: true)

      expect(result[:created]).to be(true)
      expect(Patient.where(contact_id: contact.id).count).to eq(2) # responsável + dependente
    end
  end

  # ── T13/T14/T21 — BUSCA DE HORÁRIOS ─────────────────────────────────
  describe 'T13/T14/T21 — search_available_slots' do
    subject(:tool) { AiAgent::Tools::SearchAvailableSlotsTool.new(ctx) }

    it 'T13_retorna_slots_indicando_o_profissional_disponivel' do
      service, professional = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week)

      expect(result[:available]).to be(true)
      expect(result[:slots]).not_to be_empty
      expect(result[:slots].first[:available_with].map { |p| p[:id] }).to include(professional.id)
    end

    # Regressão 2026-06-11: a Bia INVENTOU only_user_id=1 (Dr. era 721), o
    # erro genérico não se autocorrigia e ela disse ao paciente que o horário
    # estava ocupado — com a agenda 100% livre. O erro tem que devolver os
    # profissionais válidos e proibir a conclusão de "agenda cheia".
    it 'T13_user_id_inventado_devolve_profissionais_validos_e_proibe_dizer_ocupado' do
      service, professional = setup_agenda!

      result = tool.execute(service_id: service.id, from_date: from_next_week, only_user_id: 999_999)

      expect(result[:available]).to be(false)
      expect(result[:valid_professionals].map { |p| p[:id] }).to include(professional.id)
      expect(result[:note_for_bea]).to match(/profissional ERRADO/i)
      expect(result[:note_for_bea]).to match(/PROIBIDO.*ocupado/i)
    end

    it 'T13_servico_sem_profissional_informa_que_nao_atende_e_lista_alternativas' do
      # serviço COM profissional (o que a clínica atende de verdade)
      atendido, = setup_agenda!
      # serviço SEM profissional (ex.: "Implante" cadastrado mas sem ninguém)
      implante = create(:agenda_service, account: account, name: 'Implante')

      result = tool.execute(service_id: implante.id, from_date: from_next_week)

      expect(result[:available]).to be(false)
      expect(result[:slots]).to be_empty
      expect(result[:available_services].map { |s| s[:id] }).to include(atendido.id)
      expect(result[:available_services].map { |s| s[:id] }).not_to include(implante.id)
      expect(result[:note_for_bea]).to match(/NÃO atende/i)
      expect(result[:note_for_bea]).not_to match(/transfer_to_human/)
    end

    # Regressão 2026-06-12: paciente pedia 14h15/14h30 e a Bia negava ("não
    # disponível, mas tem às 14h") — a grade anda de hora em hora e o horário
    # quebrado nunca existia nela. Pedido exato agora é validado direto.
    it 'T14_horario_quebrado_pedido_pelo_paciente_e_livre_aparece_na_oferta' do
      service, = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week, requested_time: '14:30')

      expect(result[:available]).to be(true)
      expect(result[:slots].map { |s| s[:time] }).to include('14:30')
    end

    it 'T14_horario_quebrado_conflitando_com_evento_NAO_aparece' do
      service, professional = setup_agenda!
      dia = Date.parse(from_next_week)
      # no fuso da CLÍNICA — o allocator monta os slots em America/Sao_Paulo
      brt = ActiveSupport::TimeZone.new('America/Sao_Paulo')
      busy = brt.local(dia.year, dia.month, dia.day, 14, 0)
      create(:agenda_event, account: account, user: professional,
                            starts_at: busy, ends_at: busy + 1.hour, status: 'scheduled')

      # janela fixa NO dia do conflito (sem to_date a busca avança pro próximo
      # dia e acharia 14:30 livre lá — comportamento desejado, mas fora do
      # que este teste verifica)
      result = tool.execute(service_id: service.id, from_date: from_next_week,
                            to_date: from_next_week, requested_time: '14:30')

      expect(result[:slots].map { |s| s[:time] }).not_to include('14:30')
    end

    it 'T14_oferta_espontanea_continua_so_com_horarios_da_grade' do
      service, = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week, period: 'qualquer')

      # grade anda pela duração (60min) a partir da abertura — nada de :15/:30
      expect(result[:slots].map { |s| s[:time].split(':').last }).to all(eq('00'))
    end

    it 'T14_oferece_no_maximo_3_horarios' do
      service, = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week, period: 'qualquer')

      expect(result[:slots].size).to be_between(1, 3)
      expect(result[:total_found]).to eq(result[:slots].size)
    end

    it 'T14_respeita_o_periodo_pedido_manha' do
      service, = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week, period: 'manha')

      expect(result[:slots]).not_to be_empty
      hours = result[:slots].map { |s| s[:time].split(':').first.to_i }
      expect(hours).to all(be_between(5, 11)) # nenhum slot fora da manhã
    end

    it 'T14_leque_da_tarde_inclui_o_horario_mais_tarde' do
      # Bug do dono: clínica vai até 18h mas ela só oferecia 13/14/15 e negava
      # 16/17. O leque do período DEVE representar a faixa até o fim (>=16h).
      service, = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week, period: 'tarde')

      expect(result[:slots].size).to be_between(1, 3)
      latest_hour = result[:slots].map { |s| s[:time].split(':').first.to_i }.max
      expect(latest_hour).to be >= 16
    end

    it 'T14_periodo_qualquer_inclui_o_horario_mais_tarde' do
      # Bug do dono: no reagendamento (period 'qualquer') ela mostrava só os
      # primeiros (09/10/13) e escondia o 17h, dizendo que a clínica fecha
      # cedo. Num dia útil (vai até 18h), o leque tem que incluir o ÚLTIMO
      # horário, não só os da manhã. (Sábado fecha 13h — por isso uso seg.)
      service, = setup_agenda!
      weekday = Date.current.next_occurring(:monday).iso8601
      result = tool.execute(service_id: service.id, from_date: weekday, to_date: weekday, period: 'qualquer')

      latest_hour = result[:slots].map { |s| s[:time].split(':').first.to_i }.max
      expect(latest_hour).to be >= 16
    end

    it 'T17_horario_especifico_pedido_aparece_na_oferta' do
      # Se o paciente pede "17h" e está livre, a oferta tem que conter 17:00
      # (não negar um horário que existe).
      service, = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week, period: 'tarde', requested_time: '17:00')

      expect(result[:slots].map { |s| s[:time] }).to include('17:00')
    end

    it 'T17_horario_especifico_aparece_mesmo_no_periodo_qualquer' do
      # Bug do dono (06/06): pedindo "17h" SEM período (qualquer), a tool saía
      # cedo e ignorava o requested_time, devolvendo o spread padrão e negando
      # um horário livre. O horário pedido tem que aparecer em qualquer período.
      service, = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week, period: 'qualquer', requested_time: '17:00')

      expect(result[:slots].map { |s| s[:time] }).to include('17:00')
    end

    it 'T21_janela_default_eh_de_7_dias' do
      window = AiAgent::Tools::SearchAvailableSlotsTool::DateRangeValidator.call(from_date: '2026-07-06')

      expect(window.error_message).to be_nil
      expect((window.to - window.from).to_i).to eq(7)
    end

    it 'T21_janela_maior_que_14_dias_eh_recusada' do
      window = AiAgent::Tools::SearchAvailableSlotsTool::DateRangeValidator
               .call(from_date: '2026-07-06', to_date: '2026-08-06')

      expect(window.error_message).to match(/14 dias/)
    end

    it 'T17_sem_disponibilidade_na_janela_sugere_alargar_ou_lista_de_espera' do
      # Clínica fecha às 18h → não existe slot "noite" (>=18h): janela
      # devolve vazio e a tool orienta a Bia a oferecer outra opção/lista.
      service, = setup_agenda!
      result = tool.execute(service_id: service.id, from_date: from_next_week, period: 'noite')

      expect(result[:available]).to be(false)
      expect(result[:slots]).to be_empty
      expect(result[:note_for_bea]).to match(/alargar|lista de espera|outro período/i)
    end
  end

  # ── T16 — AGENDAMENTO + endereço da clínica ─────────────────────────
  describe 'T16 — book_appointment + clinic_info' do
    it 'T16_agenda_como_scheduled_origem_ai_agent' do
      service, professional = setup_agenda!
      create(:patient, account: account, name: 'Mariana Souza', contact_id: contact.id)
      starts = (7.days.from_now).change(hour: 10, min: 0)

      result = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(
        starts_at: starts.iso8601, duration_minutes: 60, title: 'Avaliação',
        user_id: professional.id, service_id: service.id
      )

      expect(result[:booked]).to be(true)
      expect(result[:confirmation_pending]).to be(false) # Bia fecha sozinha
      event = AgendaEvent.find(result[:appointment][:id])
      expect(event.status).to eq('scheduled')
      expect(event.source).to eq('ai_agent')
      expect(event.contact_id).to eq(contact.id)
    end

    it 'T16_recusa_agendar_sem_ficha_de_paciente' do
      service, professional = setup_agenda!
      # contato SEM Patient cadastrado → recusa pra NÃO criar evento órfão
      starts = (7.days.from_now).change(hour: 10, min: 0)

      result = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(
        starts_at: starts.iso8601, duration_minutes: 60, title: 'Avaliação',
        user_id: professional.id, service_id: service.id
      )

      expect(result[:booked]).to be(false)
      expect(result[:needs_patient]).to be(true)
      expect(AgendaEvent.where(contact_id: contact.id).count).to eq(0)
    end

    # 2026-06-12: a Bia NUNCA pode agendar um par profissional×serviço que
    # não existe — service_id e user_id agora são obrigatórios e validados.
    it 'T16_recusa_agendar_sem_service_id_ou_sem_user_id' do
      service, professional = setup_agenda!
      create(:patient, account: account, name: 'Mariana Souza', contact_id: contact.id)
      starts = (7.days.from_now).change(hour: 10, min: 0)

      sem_servico = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(
        starts_at: starts.iso8601, title: 'Avaliação', user_id: professional.id, service_id: nil
      )
      sem_prof = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(
        starts_at: starts.iso8601, title: 'Avaliação', user_id: nil, service_id: service.id
      )

      expect(sem_servico[:booked]).to be(false)
      expect(sem_servico[:needs_service]).to be(true)
      expect(sem_prof[:booked]).to be(false)
      expect(sem_prof[:needs_professional]).to be(true)
      expect(AgendaEvent.where(contact_id: contact.id).count).to eq(0)
    end

    it 'T16_recusa_profissional_que_nao_realiza_o_servico_e_lista_os_validos' do
      service, professional = setup_agenda!
      create(:patient, account: account, name: 'Mariana Souza', contact_id: contact.id)
      outro = create(:user, account: account, role: :agent, name: 'Carlos Lima')
      starts = (7.days.from_now).change(hour: 10, min: 0)

      result = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(
        starts_at: starts.iso8601, title: 'Avaliação', user_id: outro.id, service_id: service.id
      )

      expect(result[:booked]).to be(false)
      expect(result[:valid_professionals].map { |p| p[:id] }).to eq([professional.id])
      expect(AgendaEvent.where(contact_id: contact.id).count).to eq(0)
    end

    it 'T16_idempotente_nao_duplica_mesmo_slot' do
      service, professional = setup_agenda!
      create(:patient, account: account, name: 'Mariana Souza', contact_id: contact.id)
      starts = (7.days.from_now).change(hour: 10, min: 0)
      args = { starts_at: starts.iso8601, duration_minutes: 60, title: 'Avaliação',
               user_id: professional.id, service_id: service.id }

      first = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(**args)
      second = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(**args)

      expect(first[:booked]).to be(true)
      expect(second[:duplicate]).to be(true)
      expect(AgendaEvent.where(contact_id: contact.id).where.not(status: 'cancelled').count).to eq(1)
    end

    it 'T16_clinic_info_devolve_endereco_e_link_do_maps' do
      AgendaSetting.create!(account: account)
      account.update!(custom_attributes: {
                        'fantasy_name' => 'Clínica Streit', 'phone' => '(11) 97557-7204',
                        'address_street' => 'Rua Eugênio Lessmann', 'address_number' => '130',
                        'address_neighborhood' => 'Centro', 'address_city' => 'Jaraguá do Sul',
                        'address_state' => 'SC', 'address_zip' => '89252-030'
                      })

      result = AiAgent::Tools::ClinicInfoTool.new(ctx).execute

      expect(result[:clinic]).to be_present
      expect(result[:clinic][:address_text]).to include('Rua Eugênio Lessmann', 'Jaraguá do Sul/SC')
      expect(result[:clinic][:maps_url]).to start_with('https://www.google.com/maps/search/?api=1&query=')
    end
  end

  # ── T22 — agendamento para TERCEIRO (não o titular do WhatsApp) ──────
  describe 'T22 — agendamento de terceiro respeita patient_id' do
    it 'T22_book_para_terceiro_grava_patient_id_do_dependente' do
      service, professional = setup_agenda!
      create(:patient, account: account, name: 'Patricia Gomes', contact_id: contact.id) # titular
      dependente = create(:patient, account: account, name: 'Pedro Gomes', contact_id: contact.id)
      starts = (8.days.from_now).change(hour: 11, min: 0)

      result = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(
        starts_at: starts.iso8601, duration_minutes: 60, title: 'Avaliação Pedro',
        user_id: professional.id, service_id: service.id, patient_id: dependente.id
      )

      expect(result[:booked]).to be(true)
      event = AgendaEvent.find(result[:appointment][:id])
      expect(event.custom_attributes['patient_id']).to eq(dependente.id)
    end

    it 'T22_recusa_patient_id_de_outro_whatsapp' do
      service, professional = setup_agenda!
      other_contact = create(:contact, account: account)
      alheio = create(:patient, account: account, name: 'Estranho', contact_id: other_contact.id)
      starts = (8.days.from_now).change(hour: 12, min: 0)

      result = AiAgent::Tools::BookAppointmentTool.new(ctx).execute(
        starts_at: starts.iso8601, duration_minutes: 60, title: 'X',
        user_id: professional.id, service_id: service.id, patient_id: alheio.id
      )

      expect(result[:booked]).to be(false)
      expect(result[:error]).to match(/não pertence a este WhatsApp/i)
    end
  end

  # ── T05/T06 — CANCELAMENTO ──────────────────────────────────────────
  describe 'T05/T06 — cancel_appointment' do
    it 'T06_cancela_marcando_status_cancelled' do
      event = create(:agenda_event, account: account, contact: contact,
                                    starts_at: (5.days.from_now).change(hour: 10),
                                    ends_at: (5.days.from_now).change(hour: 11), status: 'scheduled')

      result = AiAgent::Tools::CancelAppointmentTool.new(ctx)
                                                    .execute(appointment_id: event.id, reason: 'Imprevisto no trabalho')

      expect(result[:cancelled]).to be(true)
      expect(event.reload.status).to eq('cancelled')
      expect(event.description).to match(/Imprevisto no trabalho/)
    end

    it 'T06_nao_cancela_consulta_de_outro_paciente' do
      other = create(:contact, account: account)
      event = create(:agenda_event, account: account, contact: other,
                                    starts_at: (5.days.from_now).change(hour: 10),
                                    ends_at: (5.days.from_now).change(hour: 11), status: 'scheduled')

      result = AiAgent::Tools::CancelAppointmentTool.new(ctx).execute(appointment_id: event.id, reason: 'teste')

      expect(result[:cancelled]).to be(false)
      expect(result[:error]).to match(/não pertence/i)
      expect(event.reload.status).to eq('scheduled')
    end

    # Pedido do dono: motivo do cancelamento vai pras Observações (notes) do
    # paciente, no cadastro/prontuário.
    it 'T06_cancelamento_grava_motivo_nas_observacoes_do_paciente' do
      patient = create(:patient, account: account, name: 'Maria Souza', contact_id: contact.id)
      event = create(:agenda_event, account: account, contact: contact,
                                    starts_at: (5.days.from_now).change(hour: 10),
                                    ends_at: (5.days.from_now).change(hour: 11), status: 'scheduled',
                                    custom_attributes: { 'patient_id' => patient.id })

      AiAgent::Tools::CancelAppointmentTool.new(ctx).execute(appointment_id: event.id, reason: 'Viagem de trabalho')

      expect(patient.reload.notes.to_s).to match(/Viagem de trabalho/)
      expect(patient.notes.to_s).to match(/cancelada/i)
    end
  end

  # ── T08 — REAGENDAMENTO ─────────────────────────────────────────────
  describe 'T08 — reschedule_appointment' do
    it 'T08_remarca_mantendo_scheduled_e_move_o_horario' do
      old_start = (5.days.from_now).change(hour: 14)
      event = create(:agenda_event, account: account, contact: contact,
                                    starts_at: old_start, ends_at: old_start + 1.hour, status: 'confirmed')
      new_start = (6.days.from_now).change(hour: 15)

      result = AiAgent::Tools::RescheduleAppointmentTool.new(ctx)
                                                        .execute(appointment_id: event.id, new_starts_at: new_start.iso8601, reason: 'imprevisto')

      expect(result[:rescheduled]).to be(true)
      event.reload
      expect(event.status).to eq('scheduled') # volta pra scheduled mesmo vindo de confirmed
      expect(event.starts_at).to be_within(1.minute).of(new_start)
    end
  end

  # ── T18/T19 — LISTA DE ESPERA ───────────────────────────────────────
  describe 'T18/T19 — add_to_waiting_list' do
    subject(:tool) { AiAgent::Tools::AddToWaitingListTool.new(ctx) }

    it 'T18_entra_na_lista_de_espera_com_periodo' do
      result = tool.execute(period: 'morning', preferred_days: 'seg,qua', specific_time: '09:00')

      expect(result[:added]).to be(true)
      entry = WaitingListEntry.find(result[:entry][:id])
      expect(entry.period).to eq('morning')
      expect(entry.contact_id).to eq(contact.id)
    end

    it 'T19_upsert_nao_duplica_entrada_do_mesmo_contato' do
      first = tool.execute(period: 'morning')
      second = AiAgent::Tools::AddToWaitingListTool.new(ctx).execute(period: 'afternoon')

      expect(first[:entry][:id]).to eq(second[:entry][:id]) # mesma linha, atualizada
      expect(WaitingListEntry.where(account_id: account.id, contact_id: contact.id).count).to eq(1)
      expect(WaitingListEntry.find(second[:entry][:id]).period).to eq('afternoon')
    end

    it 'T18_recusa_periodo_invalido' do
      result = tool.execute(period: 'madrugada')

      expect(result[:added]).to be(false)
      expect(result[:error]).to match(/per[ií]odo inv/i)
    end
  end

  # ── ROTA 1 — paciente cadastrado (1.1/1.5/1.7) ──────────────────────
  describe 'ROTA1 — find_patient_by_phone (reconhecimento sem quiz)' do
    it 'T01_paciente_vinculado_nao_faz_quiz_de_identidade' do
      c = create(:contact, account: account, phone_number: '+5511988887777')
      create(:patient, account: account, name: 'Leandro Lopes', contact_id: c.id)

      result = AiAgent::Tools::FindPatientByPhoneTool.new(ctx(contact_id: c.id)).execute

      expect(result[:already_linked]).to be(true)
      expect(result[:candidates_count]).to eq(1)
      expect(result[:note_for_bea]).to match(/N[ÃA]O faça quiz|N[ÃA]O pergunte/i)
      expect(result[:note_for_bea]).not_to match(/Confirme o nome/i)
    end

    it 'T02_titular_mais_dependente_manda_perguntar_pra_quem_e' do
      c = create(:contact, account: account, phone_number: '+5511988886666')
      create(:patient, account: account, name: 'Patricia Gomes', contact_id: c.id)
      create(:patient, account: account, name: 'Pedro Gomes', contact_id: c.id)

      result = AiAgent::Tools::FindPatientByPhoneTool.new(ctx(contact_id: c.id)).execute

      expect(result[:candidates_count]).to eq(2)
      expect(result[:note_for_bea]).to match(/dependente|titular/i)
    end

    it 'T01_cadastro_achado_por_telefone_nao_vinculado_sem_quiz' do
      c = create(:contact, account: account, phone_number: '+5511977775555')
      create(:patient, account: account, name: 'Joana Silva', phone: '11977775555', contact_id: nil)

      result = AiAgent::Tools::FindPatientByPhoneTool.new(ctx(contact_id: c.id)).execute

      expect(result[:found]).to be(true)
      expect(result[:note_for_bea]).to match(/N[ÃA]O pergunte "voc[êe] é/i)
      expect(result[:note_for_bea]).not_to match(/Confirme o nome/i)
    end
  end

  describe 'ROTA1 — list_appointments por patient_id (dependente)' do
    it 'T03_filtra_consultas_da_pessoa_escolhida' do
      c = create(:contact, account: account)
      titular = create(:patient, account: account, name: 'Pai Gomes', contact_id: c.id)
      dep = create(:patient, account: account, name: 'Filho Gomes', contact_id: c.id)
      s = (5.days.from_now).change(hour: 9)
      create(:agenda_event, account: account, contact: c, starts_at: s, ends_at: s + 1.hour,
                            status: 'scheduled', custom_attributes: { 'patient_id' => dep.id, 'patient_name' => 'Filho Gomes' })
      create(:agenda_event, account: account, contact: c, starts_at: s + 2.hours, ends_at: s + 3.hours,
                            status: 'scheduled', custom_attributes: { 'patient_id' => titular.id })

      result = AiAgent::Tools::ListAppointmentsTool.new(ctx(contact_id: c.id)).execute(patient_id: dep.id)

      expect(result[:count]).to eq(1)
      expect(result[:appointments].first[:patient_id]).to eq(dep.id)
    end
  end

  describe 'ROTA1 — reagendamento mantém o doutor (1.7)' do
    it 'T08_search_only_user_id_restringe_ao_profissional' do
      service, prof = setup_agenda!
      result = AiAgent::Tools::SearchAvailableSlotsTool.new(ctx)
                                                       .execute(service_id: service.id, from_date: from_next_week, only_user_id: prof.id)

      expect(result[:available]).to be(true)
      expect(result[:slots].first[:available_with].map { |p| p[:id] }).to eq([prof.id])
    end

    it 'T08_search_only_user_id_de_quem_nao_atende_falha' do
      service, = setup_agenda!
      outro = create(:user, account: account, role: :agent)
      result = AiAgent::Tools::SearchAvailableSlotsTool.new(ctx)
                                                       .execute(service_id: service.id, from_date: from_next_week, only_user_id: outro.id)

      expect(result[:available]).to be(false)
      expect(result[:error]).to match(/NÃO realiza o serviço/i)
      # contrato auto-corretivo: devolve os válidos e proíbe "ocupado"
      expect(result[:valid_professionals]).to be_present
      expect(result[:note_for_bea]).to match(/PROIBIDO.*ocupado/i)
    end

    it 'T08_reschedule_recusa_horario_com_conflito_do_mesmo_profissional' do
      prof = create(:user, account: account, role: :agent)
      s1 = (5.days.from_now).change(hour: 10)
      ev = create(:agenda_event, account: account, contact: contact, user: prof,
                                 starts_at: s1, ends_at: s1 + 1.hour, status: 'scheduled')
      s2 = (6.days.from_now).change(hour: 15)
      create(:agenda_event, account: account, user: prof, starts_at: s2, ends_at: s2 + 1.hour, status: 'scheduled')

      result = AiAgent::Tools::RescheduleAppointmentTool.new(ctx).execute(appointment_id: ev.id, new_starts_at: s2.iso8601, reason: 'imprevisto')

      expect(result[:rescheduled]).to be_falsey
      expect(result[:error]).to match(/outro compromisso/i)
    end
  end

  # ── Bug do dono (06/06/2026): evento criado pela tela da Agenda fica com
  #    contact_id NULO; o vínculo do paciente mora só em custom_attributes.
  #    A busca antiga (where contact_id:) não achava → a Bea abria sem citar
  #    a consulta marcada. Agora cruzamos pelo patient_id do contato.
  describe 'agendamento com contact_id nulo no evento (tela da Agenda)' do
    let(:c) { create(:contact, account: account, phone_number: '+5511975577204') }
    let(:patient) do
      create(:patient, account: account, name: 'Leandro Lopes Gonçalves',
                       phone: '11975577204', contact_id: c.id)
    end

    def event_sem_contact_id!
      s = (2.days.from_now).change(hour: 14)
      ev = create(:agenda_event, account: account, starts_at: s, ends_at: s + 1.hour,
                                 status: 'scheduled',
                                 custom_attributes: { 'patient_id' => patient.id, 'patient_name' => patient.name })
      ev.update_column(:contact_id, nil) # força o cenário real: evento criado pela tela da Agenda, sem contact_id
      ev
    end

    it 'list_appointments acha o evento pelo patient_id do contato' do
      event_sem_contact_id!
      result = AiAgent::Tools::ListAppointmentsTool.new(ctx(contact_id: c.id)).execute

      expect(result[:found]).to be(true)
      expect(result[:count]).to eq(1)
      expect(result[:appointments].first[:patient_id]).to eq(patient.id)
    end

    it 'find_patient_by_phone traz a consulta e manda mencionar na abertura' do
      event_sem_contact_id!
      result = AiAgent::Tools::FindPatientByPhoneTool.new(ctx(contact_id: c.id)).execute

      expect(result[:upcoming_appointments].first[:patient_id]).to eq(patient.id)
      expect(result[:note_for_bea]).to match(/1 consulta marcada/i)
    end

    # Bug do dono (06/06): "Sim" pra remarcar/cancelar → a Bia transferia,
    # porque reschedule/cancel checavam posse só por contact_id (nulo no
    # evento). Agora a posse vale pelo patient_id do contato + backfill.
    it 'reschedule_appointment remarca evento com contact_id nulo (posse via patient_id)' do
      ev = event_sem_contact_id!
      new_start = (3.days.from_now).change(hour: 15)
      result = AiAgent::Tools::RescheduleAppointmentTool.new(ctx(contact_id: c.id))
                                                        .execute(appointment_id: ev.id, new_starts_at: new_start.iso8601, reason: 'imprevisto')

      expect(result[:rescheduled]).to be(true)
      expect(ev.reload.contact_id).to eq(c.id) # backfill religou ao contato
    end

    it 'cancel_appointment cancela evento com contact_id nulo (posse via patient_id)' do
      ev = event_sem_contact_id!
      result = AiAgent::Tools::CancelAppointmentTool.new(ctx(contact_id: c.id))
                                                    .execute(appointment_id: ev.id, reason: 'imprevisto')

      expect(result[:cancelled]).to be(true)
      expect(ev.reload.status).to eq('cancelled')
      expect(ev.reload.contact_id).to eq(c.id)
    end
  end

  # Pedido do dono: evento EXCLUÍDO na agenda (soft-delete via deleted_at) some
  # pra Bia; e a Bia conta as consultas (singular/plural) na abertura.
  describe 'evento excluído (soft-delete) + contagem de consultas' do
    it 'list_appointments NÃO mostra evento com deleted_at (excluído na agenda)' do
      c = create(:contact, account: account)
      patient = create(:patient, account: account, name: 'Ana Lima', contact_id: c.id)
      kept = create(:agenda_event, account: account, contact: c,
                                   starts_at: 2.days.from_now.change(hour: 9), ends_at: 2.days.from_now.change(hour: 10),
                                   status: 'scheduled', custom_attributes: { 'patient_id' => patient.id })
      excluido = create(:agenda_event, account: account, contact: c,
                                       starts_at: 3.days.from_now.change(hour: 9), ends_at: 3.days.from_now.change(hour: 10),
                                       status: 'scheduled', custom_attributes: { 'patient_id' => patient.id })
      excluido.update_columns(deleted_at: Time.current)

      result = AiAgent::Tools::ListAppointmentsTool.new(ctx(contact_id: c.id)).execute

      expect(result[:count]).to eq(1)
      expect(result[:appointments].map { |a| a[:id] }).to eq([kept.id])
    end

    it 'find_patient conta as consultas no plural e pede pra escolher qual' do
      c = create(:contact, account: account)
      patient = create(:patient, account: account, name: 'Ana Lima', contact_id: c.id)
      2.times do |i|
        d = (2 + i).days.from_now
        create(:agenda_event, account: account, contact: c, starts_at: d.change(hour: 9),
                              ends_at: d.change(hour: 10), status: 'scheduled',
                              custom_attributes: { 'patient_id' => patient.id })
      end

      result = AiAgent::Tools::FindPatientByPhoneTool.new(ctx(contact_id: c.id)).execute

      expect(result[:upcoming_appointments].size).to eq(2)
      expect(result[:note_for_bea]).to match(/2 consultas marcadas/)
      expect(result[:note_for_bea]).to match(/ALGUMA delas/i)
    end

    # Bug do dono: 2 consultas (uma dele, uma do filho) → ela cancelou as DUAS.
    # A listagem tem que trazer o NOME do paciente pra ela perguntar QUAL.
    it 'find_patient lista cada consulta COM o nome do paciente (desambiguar cancelar/remarcar)' do
      c = create(:contact, account: account, phone_number: '+5511975570000')
      titular = create(:patient, account: account, name: 'Leandro Lopes', phone: '11975570000', contact_id: c.id)
      dep = create(:patient, account: account, name: 'Gabriel Lopes', phone: '11975570000', contact_id: c.id)
      s = 2.days.from_now
      create(:agenda_event, account: account, contact: c, starts_at: s.change(hour: 10), ends_at: s.change(hour: 11),
                            status: 'scheduled', custom_attributes: { 'patient_id' => titular.id, 'patient_name' => 'Leandro Lopes' })
      create(:agenda_event, account: account, contact: c, starts_at: s.change(hour: 11), ends_at: s.change(hour: 12),
                            status: 'scheduled', custom_attributes: { 'patient_id' => dep.id, 'patient_name' => 'Gabriel Lopes' })

      note = AiAgent::Tools::FindPatientByPhoneTool.new(ctx(contact_id: c.id)).execute[:note_for_bea]

      expect(note).to include('Leandro Lopes')
      expect(note).to include('Gabriel Lopes')
    end
  end

  # Regressão 2026-06-11: a Bia remarcou/cancelou SEM perguntar o motivo
  # (regra do produto: motivo é obrigatório e vai pras Observações). Agora a
  # PRÓPRIA TOOL recusa reason vazio e manda perguntar.
  describe 'Motivo obrigatório em cancelamento e remarcação' do
    it 'cancel_appointment recusa sem motivo e NÃO cancela' do
      event = create(:agenda_event, account: account, contact: contact,
                                    starts_at: (5.days.from_now).change(hour: 10),
                                    ends_at: (5.days.from_now).change(hour: 11), status: 'scheduled')

      result = AiAgent::Tools::CancelAppointmentTool.new(ctx).execute(appointment_id: event.id)

      expect(result[:cancelled]).to be(false)
      expect(result[:needs_reason]).to be(true)
      expect(result[:note_for_bea]).to match(/MOTIVO/i)
      expect(event.reload.status).to eq('scheduled')
    end

    it 'reschedule_appointment recusa sem motivo e NÃO remarca' do
      old_start = (5.days.from_now).change(hour: 10)
      event = create(:agenda_event, account: account, contact: contact,
                                    starts_at: old_start, ends_at: old_start + 1.hour, status: 'scheduled')

      result = AiAgent::Tools::RescheduleAppointmentTool.new(ctx)
                                                        .execute(appointment_id: event.id,
                                                                 new_starts_at: (6.days.from_now).change(hour: 15).iso8601)

      expect(result[:rescheduled]).to be(false)
      expect(result[:needs_reason]).to be(true)
      expect(event.reload.starts_at.to_i).to eq(old_start.to_i)
    end
  end
end
