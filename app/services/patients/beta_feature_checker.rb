# app/services/patients/beta_feature_checker.rb
#
# SERVICE: BetaFeatureChecker
#
# Propósito: Mecanismo alternativo de feature flag para rollout interno
#   gradual de funcionalidades em beta. Lê de
#   `Account#custom_attributes['beta_features']` (array de strings).
#
# Por que NÃO `Featurable` (`flag_shih_tzu` + `accounts.feature_flags`)?
#   O bitmap `feature_flags` é `bigint` (signed, 8 bytes, max bit 62).
#   O Klivy chegou a 63 features em `config/features.yml` — adicionar a 64ª
#   estoura `signed bigint` (bit 63 = 2^63 = 9_223_372_036_854_775_808 >
#   max signed bigint 9_223_372_036_854_775_807). Confirmado em produção
#   ao tentar `Account.first.enable_features!(:financial_timeline_v2)` →
#   `ActiveModel::RangeError`.
#
# Trade-offs aceitos (decisão arquitetural 2026-05-06):
#   - ✅ Sem migration, sem mexer em `Featurable`/Chatwoot core.
#   - ✅ Forward-compatible: qualquer feature beta nova entra no mesmo array.
#   - ✅ Quando o Klivy migrar `feature_flags` para esquema escalável (2 colunas
#       ou numeric com bit ops), só este service muda — nenhum caller precisa
#       saber.
#   - ❌ Não aparece em "Super Admin → Manage Features" (UI nativa do Chatwoot).
#       Para ativar/desativar usa-se `account.update!(custom_attributes: ...)`
#       via console ou via Custom Attributes da account no Super Admin.
#
# Uso:
#   Patients::BetaFeatureChecker.enabled?(account, 'financial_timeline_v2')
#   # => true / false
#
# Ativação (em piloto):
#   account.update!(
#     custom_attributes: account.custom_attributes.merge(
#       'beta_features' => ['financial_timeline_v2']
#     )
#   )
#
# Multi-tenancy: a feature liga POR account — nenhum risco de vazamento.
module Patients
  class BetaFeatureChecker
    BETA_FEATURES_KEY = 'beta_features'

    # @param account [Account, nil] account a verificar (geralmente Current.account)
    # @param feature_name [String, Symbol] nome da feature beta
    # @return [Boolean]
    def self.enabled?(account, feature_name)
      return false if account.blank?
      return false if feature_name.blank?

      list = account.custom_attributes&.dig(BETA_FEATURES_KEY)
      Array(list).map(&:to_s).include?(feature_name.to_s)
    end

    # @param account [Account]
    # @return [Array<String>] lista de features beta ativas para a account
    def self.list_for(account)
      return [] if account.blank?

      Array(account.custom_attributes&.dig(BETA_FEATURES_KEY)).map(&:to_s)
    end
  end
end
