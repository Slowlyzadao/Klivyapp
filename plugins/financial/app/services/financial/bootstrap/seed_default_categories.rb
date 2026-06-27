module Financial
  module Bootstrap
    # Seed canon do Plano de Contas (DRE) — FONTE ÚNICA de verdade do canon.
    # (O antigo script `db/seeds/dre_categories_canon.rb` foi removido em
    # 2026-05-27; este service o substitui — bootstrap, restore e rake usam ele.)
    #
    # Chamada automaticamente por `Account.after_create_commit` no engine.rb
    # — toda conta nova ganha o canon completo imediatamente, sem precisar
    # rodar `rails runner` manualmente.
    #
    # Idempotente: usa `find_or_create_by` em (account_id, name, parent_id),
    # então rodar 2× não duplica. Seguro pra rodar via job/console também.
    #
    # Estrutura canon (`mapa-financeiro.json` step 2):
    #   - Sistema: "Sem categoria" (system_default)
    #   - Receitas:
    #     · Receita Clínica → Procedimentos Particulares (10 procs) | Convênios | Pacotes
    #     · Receita Não Clínica → Outras → [Aluguel, Vendas, Outras]
    #     · Estornos (system_default)
    #   - Despesas (11 grupos × N itens):
    #     · Pessoal, Ocupação, Materiais, Laboratório, Terceiros, Marketing,
    #       Impostos (com Taxa Maquininha system_default), Equipamentos,
    #       Capacitação, Financeiras, Diversas
    class SeedDefaultCategories
      Result = Financial::ServiceResult

      def self.call(account:)
        new(account: account).call
      end

      def initialize(account:)
        @account = account
        @created = 0
        @skipped = 0
      end

      def call
        return Result.failure('account required') if @account.nil?

        ActiveRecord::Base.transaction do
          seed_system!
          seed_revenues!
          seed_expenses!
        end

        Result.success(
          account_id: @account.id,
          created: @created,
          skipped: @skipped,
          total: ::Financial::DreCategory.for_account(@account.id).alive.count
        )
      rescue ActiveRecord::RecordInvalid => e
        Result.failure(e.record.errors.full_messages.join('; '))
      end

      private

      def seed_system!
        create_category!(name: 'Sem categoria', kind: 'outra_despesa', system_default: true)
      end

      def seed_revenues!
        # 1. Receita Clínica → Procedimentos Particulares
        g_clinica = create_category!(name: 'Receita Clínica', kind: 'receita')
        sg_particulares = create_category!(name: 'Procedimentos Particulares', kind: 'receita', parent: g_clinica)
        %w[
          Clínica\ Geral
          Endodontia
          Periodontia
          Implantodontia
          Prótese
          Ortodontia
          Odontopediatria
          Estética
          Cirurgia
          Outros\ Procedimentos
        ].each do |proc|
          create_category!(name: proc, kind: 'receita', parent: sg_particulares)
        end

        # 1.2 Convênios
        create_category!(name: 'Convênios e Planos de Saúde', kind: 'receita', parent: g_clinica)

        # 1.3 Pacotes
        sg_pacotes = create_category!(name: 'Pacotes e Planos Internos', kind: 'receita', parent: g_clinica)
        create_category!(name: 'Pacotes por Tratamento', kind: 'receita', parent: sg_pacotes)
        create_category!(name: 'Planos de Manutenção', kind: 'receita', parent: sg_pacotes)

        # 2. Receita Não Clínica → Outras → items
        g_nao_clinica = create_category!(name: 'Receita Não Clínica', kind: 'receita')
        sg_outras = create_category!(name: 'Outras', kind: 'receita', parent: g_nao_clinica)
        %w[Aluguel\ de\ Espaço Venda\ de\ Produtos Outras\ Receitas].each do |item|
          create_category!(name: item, kind: 'receita', parent: sg_outras)
        end

        # Estornos (system_default — invisível na UI normal)
        create_category!(name: 'Estornos', kind: 'receita', system_default: true)
      end

      def seed_expenses!
        DESPESAS_CANON.each do |grupo_name, itens|
          grupo = create_category!(name: grupo_name, kind: 'outra_despesa')
          itens.each do |item_name|
            is_system = item_name == 'Taxa de Maquininha e Cartão'  # auto-MDR
            create_category!(name: item_name, kind: 'outra_despesa', parent: grupo, system_default: is_system)
          end
        end
      end

      DESPESAS_CANON = {
        'Pessoal' => [
          'Salários e Ordenados', 'Encargos Sociais', 'Pró-labore',
          'Comissões de Profissionais', 'Benefícios', 'Rescisões'
        ],
        'Ocupação' => [
          'Aluguel', 'Condomínio', 'Energia Elétrica', 'Água e Esgoto',
          'Internet e Telefone', 'IPTU'
        ],
        'Materiais e Insumos' => [
          'Materiais Odontológicos', 'EPI e Descartáveis', 'Material de Escritório'
        ],
        'Laboratório' => [
          'Próteses e Trabalhos Protéticos', 'Aparelhos Ortodônticos',
          'Outros Serviços de Laboratório'
        ],
        'Serviços de Terceiros' => [
          'Contabilidade', 'Assessoria Jurídica', 'TI / Sistema de Gestão',
          'Limpeza e Conservação', 'Outros Serviços'
        ],
        'Marketing e Captação' => [
          'Meta Ads', 'Google Ads', 'Produção de Conteúdo',
          'Material Gráfico e Impresso', 'Site e SEO', 'Outros Canais'
        ],
        'Impostos e Taxas' => [
          'Simples Nacional (DAS Mensal)', 'ISS (se fora do Simples)',
          'Taxa de Maquininha e Cartão', 'Taxas Bancárias'
        ],
        'Equipamentos e Manutenção' => [
          'Manutenção de Equipamentos', 'Calibração e Certificação',
          'Manutenção Predial', 'Depreciação'
        ],
        'Capacitação e Desenvolvimento' => [
          'Cursos e Congressos', 'Anuidade CRO e Associações', 'Assinaturas'
        ],
        'Despesas Financeiras' => [
          'Juros e Multas', 'IOF', 'Tarifas Bancárias'
        ],
        'Despesas Diversas' => [
          'Uniformes e EPIs Administrativos', 'Seguros', 'Outros'
        ]
      }.freeze

      # Helper genérico — idempotente via find_by + create_or_update.
      # Update mínimo (só system_default flag) se já existir — não sobrescreve
      # ordenação, cor, ou outras edições da clínica.
      def create_category!(name:, kind:, parent: nil, system_default: false)
        scope = ::Financial::DreCategory.for_account(@account.id).alive
        # Categorias de sistema têm nome único por conta (Estornos, Sem categoria,
        # Taxa de Maquininha). Casamos por (name, parent) IGNORANDO o kind — senão
        # uma conta legada com kind divergente (ex: "Estornos" gravado como despesa)
        # faria o seed criar uma duplicata `receita` a cada restore/bootstrap.
        # Categorias normais continuam casando por kind (uma "Aluguel" receita ≠ despesa).
        existing =
          if system_default
            scope.find_by(name: name, parent_id: parent&.id)
          else
            scope.find_by(name: name, parent_id: parent&.id, kind: kind)
          end

        if existing
          # Corrige system_default se mudou (ex: canon agora marca como system mas não estava).
          # NÃO mexemos no kind de uma system_default existente: o DRE ainda não modela
          # deduções, então flipar "Estornos" de despesa→receita sumiria os estornos do
          # relatório (saída + kind receita não é somada em nenhuma seção). Correção de
          # kind fica como follow-up junto com a seção "Deduções/Estornos" no DRE.
          if existing.system_default != system_default && system_default
            existing.update_columns(system_default: true, updated_at: Time.current)
          end
          @skipped += 1
          return existing
        end

        cat = ::Financial::DreCategory.create!(
          account_id: @account.id,
          parent_id: parent&.id,
          name: name,
          kind: kind,
          system_default: system_default,
          color: kind == 'receita' ? '#10b981' : '#ef4444'
        )
        @created += 1
        cat
      end
    end
  end
end
