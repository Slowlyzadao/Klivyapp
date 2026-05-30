# frozen_string_literal: true

module DocumentTemplates
  # Estrutura imutável que representa uma variável do catálogo.
  #
  # `key`        — chave canônica usada no JSON do TipTap (`patient.full_name`).
  # `label`      — texto exibido no chip e no menu de inserção.
  # `category`   — agrupador no UI ('Paciente', 'Clínica', etc.).
  # `example`    — valor de exemplo mostrado na hover do menu (educa o user).
  # `formatter`  — símbolo do helper Ruby aplicado ao valor (:cpf, :date_long...).
  # `description` — explicação livre (opcional, aparece no tooltip).
  Variable = Struct.new(
    :key,
    :label,
    :category,
    :example,
    :formatter,
    :description,
    keyword_init: true
  ) do
    # Hash plano usado pelo endpoint público `GET /document_templates/variables`.
    # Frontend cacheia essa lista e usa pra popular o menu de inserção do "/".
    def to_public_hash
      {
        key: key,
        label: label,
        category: category,
        example: example,
        description: description
      }
    end
  end
end
