# frozen_string_literal: true

module Signatures
  # Erro genérico levantado pelos providers de assinatura.
  #
  # Mora em arquivo próprio (em vez de dentro de provider.rb) por causa do
  # autoload do Zeitwerk: como `DownloadSignedPdfJob` referencia
  # `Signatures::ProviderError` já no corpo da classe (`retry_on`) e o
  # `ProviderResolver` faz `raise ProviderError`, em desenvolvimento (lazy
  # load) o Zeitwerk procura `signatures/provider_error.rb`. Se a constante
  # vivesse em provider.rb, daria `uninitialized constant` até Provider ser
  # carregado.
  class ProviderError < StandardError; end
end
