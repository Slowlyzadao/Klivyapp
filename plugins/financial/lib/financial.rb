module Financial
  def self.table_name_prefix
    'financial_'
  end
end

# Carrega componentes do plugin que vivem em `lib/` mas precisam estar disponíveis
# como constantes em runtime (Engine não autoloada lib/ por padrão e
# `plugins/*/lib` não está garantido no $LOAD_PATH — então usamos require_relative).
# Estes arquivos só definem classes/módulos sob `Financial::*` (sem boot side-effects).
require_relative 'financial/gateways'
require_relative 'financial/gateways/base'
require_relative 'financial/gateways/manual'
require_relative 'financial/gateways/asaas'
