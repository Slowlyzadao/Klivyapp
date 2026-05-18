module AiAgent
  module InternalNotifier
    # Catálogo central dos eventos que a Bea pode notificar no Chat Interno.
    # Cada evento descreve: label exibido na UI, descrição curta, variáveis
    # disponíveis no template (substituídas via `format(body, vars)`), default
    # role da sala recomendada, e body padrão pré-preenchido na criação.
    #
    # `detector_status: :active` significa que o gatilho já dispara em produção.
    # `:planned` significa que o template existe mas a detecção ainda não foi
    # implementada (UI mostra aviso "disparo automático em breve").
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
    module EventCatalog
      EVENTS = {
        'appointment_pending_confirmation' => {
          label: 'Agendamento aguardando confirmação',
          description: 'A Bea reservou um horário e a clínica precisa revisar e confirmar antes de avisar o paciente.',
          available_vars: %w[patient_name patient_phone service_name dentist_name appointment_starts_at last_visit_line patient_status],
          default_target_role: 'reception',
          detector_status: :active,
          icon: 'calendar-clock',
          color: 'sky',
          default_body: <<~BODY,
            Pessoal, novo paciente! 👋

            📋 *%{patient_name}* %{patient_status}
            📞 %{patient_phone}
            🦷 %{service_name} com %{dentist_name}
            📅 %{appointment_starts_at}
            %{last_visit_line}
            Status: aguardando confirmação. Podem revisar e confirmar pra eu avisar o paciente que está tudo certo? 🙏
          BODY
        },

        'appointment_booking_failed' => {
          label: 'Bea não conseguiu agendar',
          description: 'A Bea tentou agendar para o paciente mas falhou (slot ocupou, faltou info, etc).',
          available_vars: %w[patient_name patient_phone reason],
          default_target_role: 'reception',
          detector_status: :active,
          icon: 'alert-triangle',
          color: 'amber',
          default_body: <<~BODY,
            Pessoal, atenção 🙋

            Tentei agendar para *%{patient_name}* (%{patient_phone}) mas não consegui finalizar.

            Motivo: %{reason}

            Podem entrar em contato com o paciente?
          BODY
        },

        'patient_refund_request' => {
          label: 'Pedido de estorno / contestação',
          description: 'Paciente mencionou estorno, reembolso ou contestação de cobrança na conversa.',
          available_vars: %w[patient_name patient_phone conversation_link summary],
          default_target_role: 'financial',
          detector_status: :active,
          icon: 'refund',
          color: 'rose',
          default_body: <<~BODY,
            Atenção financeiro 💸

            *%{patient_name}* (%{patient_phone}) pediu estorno/contestação.

            Resumo: %{summary}

            Conversa: %{conversation_link}
          BODY
        },

        'patient_with_debt_booking' => {
          label: 'Paciente com débito tentando agendar',
          description: 'Paciente com pendência financeira aberta tentou agendar uma consulta nova.',
          available_vars: %w[patient_name patient_phone debt_amount debt_summary],
          default_target_role: 'financial',
          detector_status: :active,
          icon: 'credit-card',
          color: 'orange',
          default_body: <<~BODY,
            Pessoal financeiro 📋

            *%{patient_name}* (%{patient_phone}) tentou agendar mas tem pendência aberta.

            Débito: %{debt_amount}
            %{debt_summary}

            Como vocês querem que eu prossiga com o paciente?
          BODY
        },

        'clinical_emergency_detected' => {
          label: 'Emergência clínica detectada',
          description: 'Detector identificou sinais de emergência (sangramento intenso, dor severa, anafilaxia).',
          available_vars: %w[patient_name patient_phone trigger_terms conversation_link],
          default_target_role: 'reception',
          detector_status: :active,
          icon: 'siren',
          color: 'red',
          default_body: <<~BODY,
            🚨 EMERGÊNCIA CLÍNICA 🚨

            *%{patient_name}* (%{patient_phone}) está descrevendo o quê parece ser uma emergência.

            Sinais detectados: %{trigger_terms}

            Já orientei a buscar atendimento. Conversa: %{conversation_link}
          BODY
        },

        'suicidal_ideation_detected' => {
          label: 'Ideação suicida detectada (CVV)',
          description: 'Detector identificou possível ideação suicida — exige resposta humana qualificada imediata.',
          available_vars: %w[patient_name patient_phone conversation_link],
          default_target_role: 'reception',
          detector_status: :active,
          icon: 'heart-pulse',
          color: 'rose',
          default_body: <<~BODY,
            ⚠️ ATENÇÃO — possível ideação suicida

            *%{patient_name}* (%{patient_phone}) demonstrou sinais que podem indicar crise.

            Já encaminhei pro CVV (188) e orientei buscar suporte. Conversa: %{conversation_link}

            Por favor, alguém qualificado pode acompanhar essa situação.
          BODY
        },

        'offensive_patient_tone' => {
          label: 'Cliente ofensivo / agressivo',
          description: 'Detector identificou linguagem hostil, ofensa ou abuso na conversa.',
          available_vars: %w[patient_name patient_phone trigger_terms conversation_link],
          default_target_role: 'reception',
          detector_status: :active,
          icon: 'shield-alert',
          color: 'amber',
          default_body: <<~BODY,
            Atenção 🛑

            *%{patient_name}* (%{patient_phone}) está em tom hostil/ofensivo.

            Termos detectados: %{trigger_terms}

            Conversa: %{conversation_link}

            Como vocês querem que eu siga?
          BODY
        },

        'appointment_cancelled_by_patient' => {
          label: 'Paciente cancelou agendamento',
          description: 'Agendamento foi cancelado (paciente desmarcou ou recepção cancelou pelo paciente).',
          available_vars: %w[patient_name patient_phone service_name dentist_name appointment_starts_at],
          default_target_role: 'reception',
          detector_status: :active,
          icon: 'x-circle',
          color: 'orange',
          default_body: <<~BODY,
            Aviso de cancelamento ❌

            *%{patient_name}* (%{patient_phone}) cancelou o agendamento:
            🦷 %{service_name} com %{dentist_name}
            📅 %{appointment_starts_at}

            Slot está livre — vale tentar reagendar com alguém da fila?
          BODY
        },

        'appointment_no_show' => {
          label: 'Paciente faltou à consulta (no-show)',
          description: 'Consulta foi marcada como falta (paciente não compareceu).',
          available_vars: %w[patient_name patient_phone service_name dentist_name appointment_starts_at],
          default_target_role: 'reception',
          detector_status: :active,
          icon: 'user-x',
          color: 'amber',
          default_body: <<~BODY,
            Falta registrada 📋

            *%{patient_name}* (%{patient_phone}) não compareceu:
            🦷 %{service_name} com %{dentist_name}
            📅 %{appointment_starts_at}

            Vale entrar em contato pra reagendar?
          BODY
        },

        'bea_repeated_failures' => {
          label: 'Bea falhou várias vezes seguidas',
          description: 'A Bea respondeu "vou checar com a equipe" 3+ vezes seguidas — pode haver lacuna no conhecimento.',
          available_vars: %w[patient_name patient_phone failure_count topics conversation_link],
          default_target_role: 'reception',
          detector_status: :active,
          icon: 'help-circle',
          color: 'slate',
          default_body: <<~BODY,
            Pessoal 🤔

            Não estou conseguindo responder *%{patient_name}* (%{patient_phone}) em alguns pontos.

            Fui evasiva %{failure_count} vezes nos seguintes assuntos: %{topics}

            Pode ser falta de info no meu material — vale alguém revisar.

            Conversa: %{conversation_link}
          BODY
        }
      }.freeze

      def self.keys
        EVENTS.keys
      end

      def self.label_for(event_key)
        EVENTS.dig(event_key, :label) || event_key
      end

      def self.vars_for(event_key)
        EVENTS.dig(event_key, :available_vars) || []
      end

      def self.default_body_for(event_key)
        EVENTS.dig(event_key, :default_body)
      end

      def self.default_name_for(event_key)
        label_for(event_key)
      end

      def self.default_target_role_for(event_key)
        EVENTS.dig(event_key, :default_target_role) || 'reception'
      end

      def self.detector_status_for(event_key)
        EVENTS.dig(event_key, :detector_status) || :planned
      end

      def self.entry(event_key)
        EVENTS[event_key]
      end
    end
  end
end
