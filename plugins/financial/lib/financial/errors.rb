module Financial
  # Hierarquia de exceções de domínio do módulo financeiro.
  #
  # `Error` é a base. Controllers de `Api::V1::Accounts::Financial::*` mapeiam
  # cada subclasse para um status HTTP semântico em `rescue_from`:
  #
  #   PeriodClosed          → 423 Locked
  #   TenantMismatch        → 403 Forbidden
  #   FrozenAttributeError  → 422 Unprocessable Entity
  #   IdempotencyMismatch   → 422 Unprocessable Entity
  #   InvariantViolation    → 422 Unprocessable Entity (catch-all de invariantes)
  #
  # Usar exceções (em vez de retornar ServiceResult.failure em tudo) faz sentido
  # apenas para violações de invariante que NÃO devem ser silenciadas — caso
  # contrário cuidamos via `ServiceResult`. Regra de thumb:
  #
  #   * "operador tentou algo inválido" → ServiceResult.failure (esperado)
  #   * "estado do sistema é incoerente" → raise Financial::Error (excepcional)
  module Errors
    class Error < StandardError; end

    # Tentativa de criar/editar Entry/Installment/Expense em mês fechado
    # contábilmente. Reabrir via Financial::Governance::ReopenPeriod (ADMIN).
    class PeriodClosed < Error
      attr_reader :period_date

      def initialize(message = nil, period_date: nil)
        @period_date = period_date
        super(message || "Período #{period_date&.strftime('%m/%Y')} está fechado")
      end
    end

    # Tentativa de acessar/manipular registro de outro tenant.
    # Não deve ocorrer em código bem escrito (controllers usam for_account);
    # se ocorrer, é bug de implementação.
    class TenantMismatch < Error; end

    # Tentativa de mudar coluna marcada com `frozen_attributes`.
    # Auditable transforma isso em validation error normalmente; esta exceção
    # é pra paths que pulam validação (update_columns, etc).
    class FrozenAttributeError < Error
      attr_reader :attribute_name

      def initialize(attribute_name)
        @attribute_name = attribute_name
        super("Coluna `#{attribute_name}` é imutável após criação (snapshot histórico)")
      end
    end

    # Idempotency-Key reutilizado com payload diferente.
    class IdempotencyMismatch < Error
      def initialize(message = nil)
        super(message || 'Idempotency-Key reutilizado com payload diferente')
      end
    end

    # Violação genérica de invariante financeira (saldo, soma de parcelas, etc).
    # Use subclasses específicas quando possível.
    class InvariantViolation < Error; end

    # Específicas de invariantes comuns:
    class OverPayment < InvariantViolation
      def initialize(message = nil)
        super(message || 'Soma de pagamentos excede valor da parcela')
      end
    end

    class InsufficientBalance < InvariantViolation
      def initialize(message = nil)
        super(message || 'Saldo insuficiente na conta de origem')
      end
    end

    class SetupIncomplete < Error
      def initialize(message = nil)
        super(message || 'Setup financeiro incompleto — complete o wizard antes de operar')
      end
    end
  end
end
