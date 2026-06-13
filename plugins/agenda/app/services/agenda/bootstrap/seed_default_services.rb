module Agenda
  module Bootstrap
    # Seed canon de AgendaServices padrão — espelha as 10 categorias DRE L3
    # criadas por `Financial::Bootstrap::SeedDefaultCategories`.
    #
    # Vantagem desse espelhamento: o modal `ServicePricingFormModalV2` no
    # `/financial/v2/settings/services` faz auto-sugestão por nome — como os
    # nomes batem 1-pra-1, a categoria DRE correta é pré-selecionada
    # automaticamente quando a clínica clicar em "Configurar preço".
    #
    # Duração padrão e cor por procedimento são valores sensatos da prática
    # odontológica — operador edita conforme oferta da clínica em
    # `/agenda/settings > Serviços`.
    #
    # Idempotente: usa `find_or_create_by` por (account_id, name) — rodar 2x
    # não duplica. Preserva edições da clínica.
    class SeedDefaultServices
      Result = Struct.new(:success?, :created, :skipped, :errors, keyword_init: true)

      # Espelho dos 10 procedimentos canon do `mapa-financeiro.json` step 2
      # (Receita Clínica > Procedimentos Particulares).
      DEFAULT_SERVICES = [
        { name: 'Clínica Geral',         duration_minutes: 60,  color: '#3b82f6', external_id: 'canon:clinica_geral' },
        { name: 'Endodontia',            duration_minutes: 90,  color: '#ef4444', external_id: 'canon:endodontia' },
        { name: 'Periodontia',           duration_minutes: 60,  color: '#eab308', external_id: 'canon:periodontia' },
        { name: 'Implantodontia',        duration_minutes: 120, color: '#8b5cf6', external_id: 'canon:implantodontia' },
        { name: 'Prótese',               duration_minutes: 90,  color: '#06b6d4', external_id: 'canon:protese' },
        { name: 'Ortodontia',            duration_minutes: 30,  color: '#6366f1', external_id: 'canon:ortodontia' },
        { name: 'Odontopediatria',       duration_minutes: 45,  color: '#ec4899', external_id: 'canon:odontopediatria' },
        { name: 'Estética',              duration_minutes: 60,  color: '#f97316', external_id: 'canon:estetica' },
        { name: 'Cirurgia',              duration_minutes: 90,  color: '#dc2626', external_id: 'canon:cirurgia' },
        { name: 'Outros Procedimentos',  duration_minutes: 60,  color: '#94a3b8', external_id: 'canon:outros_procedimentos' }
      ].freeze

      def self.call(account:)
        new(account: account).call
      end

      def initialize(account:)
        @account = account
        @created = 0
        @skipped = 0
      end

      def call
        return failure('account required') if @account.nil?

        DEFAULT_SERVICES.each do |svc|
          create_service!(svc)
        end

        Result.new(
          success?: true,
          created: @created,
          skipped: @skipped,
          errors: []
        )
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record.errors.full_messages.join('; '))
      end

      private

      def failure(msg)
        Result.new(success?: false, created: @created, skipped: @skipped, errors: Array(msg))
      end

      # Idempotente por (account_id, external_id) — unique index do schema.
      # Se já existir, pula sem alterar (preserva edições da clínica).
      def create_service!(attrs)
        # Busca primeiro por external_id (mais estável que name — operador
        # pode renomear, external_id permanece canon)
        existing = ::AgendaService
                     .where(account_id: @account.id, external_id: attrs[:external_id])
                     .first

        # Fallback: busca por name (caso external_id ainda não existia)
        existing ||= ::AgendaService
                       .where(account_id: @account.id, deleted_at: nil)
                       .where('LOWER(btrim(name)) = ?', attrs[:name].downcase.strip)
                       .first

        if existing
          # Preenche external_id se ainda não tinha
          if existing.external_id.blank?
            existing.update_columns(external_id: attrs[:external_id], updated_at: Time.current)
          end
          @skipped += 1
          return existing
        end

        svc = ::AgendaService.create!(
          account: @account,
          name: attrs[:name],
          duration_minutes: attrs[:duration_minutes],
          color: attrs[:color],
          external_id: attrs[:external_id]
        )
        @created += 1
        svc
      end
    end
  end
end
