module AiAgent
  module Tools
    # Returns the clinic's operational info pulled from AgendaSetting +
    # AgendaService — horários de funcionamento, serviços oferecidos,
    # regras (block_outside_working_hours, slot_interval). Bea uses this
    # to answer questions like "que horas vocês abrem?", "quais serviços
    # vocês fazem?", "quanto custa X?".
    #
    # No RAG / embeddings — direct AR query.
    class ClinicInfoTool < BaseTool
      description <<~DESC
        Retorna as informações operacionais da clínica: horário de
        funcionamento por dia da semana, exceções/feriados, lista de
        serviços oferecidos com duração e preço, e regras gerais. Use
        sempre que o paciente perguntar sobre horários, serviços, valores
        ou disponibilidade da clínica.
      DESC

      def execute
        return { available: false, message: 'Módulo de agenda não disponível.' } unless defined?(::AgendaSetting)

        setting = ::AgendaSetting.find_by(account_id: account.id)
        # Bea SÓ enxerga serviços com pelo menos 1 profissional vinculado.
        # Serviço sem profissional cadastrado é como se não existisse —
        # impede a Bea de oferecer agendamento que ela não conseguiria
        # cumprir. Subquery via `where(id: ...select)` em vez de
        # `joins.distinct` porque User tem colunas json que não suportam
        # DISTINCT com igualdade no Postgres. `includes(:users)` evita
        # N+1 ao listar `professionals` depois.
        services = if defined?(::AgendaService) && defined?(::AgendaServiceUser)
                     linked_ids = ::AgendaServiceUser.where(account_id: account.id).select(:agenda_service_id)
                     ::AgendaService.where(account_id: account.id, id: linked_ids)
                                    .includes(:users)
                                    .limit(50)
                   else
                     []
                   end

        {
          available: true,
          working_hours: format_week_days(setting&.week_days),
          holidays: setting&.holidays || [],
          rules: {
            block_outside_working_hours: setting&.block_outside_working_hours,
            block_lunch_break: setting&.block_lunch_break,
            slot_interval_minutes: setting&.slot_interval_minutes,
            block_past_dates: setting&.block_past_dates
          },
          # Esta lista já foi pré-filtrada — só serviços com pelo menos
          # 1 profissional cadastrado. Logo, `professionals` nunca vem
          # vazio aqui. Se o paciente pedir um serviço que não está
          # nessa lista, ASSUMA que a clínica não oferece (não tente
          # adivinhar pelo nome).
          services: services.map do |s|
            {
              id: s.id,
              name: s.name,
              duration_minutes: s.duration_minutes,
              price: s.price.to_f,
              professionals: s.users.map { |u| { id: u.id, name: AiAgent::Formatters::ProfessionalName.format(u.name) } }
            }
          end,
          note_for_bea: 'Esta é a LISTA COMPLETA de serviços que a clínica pode realmente agendar (já filtrada — só inclui serviços com profissional cadastrado). Se o paciente pedir algo que não está aqui, a clínica não oferece esse serviço — chame transfer_to_human.'
        }
      end

      private

      def format_week_days(week_days)
        return [] if week_days.blank?

        # week_days is a jsonb hash like { "monday" => { "open" => "08:00", "close" => "18:00", "closed" => false }, ... }
        # Pass through as-is so the LLM can interpret. Add labels for readability.
        labels = { 'monday' => 'segunda', 'tuesday' => 'terça', 'wednesday' => 'quarta',
                   'thursday' => 'quinta', 'friday' => 'sexta', 'saturday' => 'sábado', 'sunday' => 'domingo' }

        week_days.map do |day, info|
          { day: labels[day.to_s] || day, **(info.is_a?(Hash) ? info.symbolize_keys : { value: info }) }
        end
      end
    end
  end
end
