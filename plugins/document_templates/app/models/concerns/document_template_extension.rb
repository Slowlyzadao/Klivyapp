# Concern injetado em Document e ConsentRecord pela engine do plugin
# document_templates (via to_prepare em engine.rb).
#
# Adiciona:
#   - belongs_to :document_template (FK opcional)
#   - scopes pra distinguir caminho legado (Prawn) vs novo (Grover)
#   - helper #generated_from_template? (resposta rápida pra escolher renderer)
#   - validação de imutabilidade do rendered_html (LGPD + integridade)
#
# Quando o concern é incluído, ambos os models passam a se comportar como
# "documentos com OU sem template". Documentos antigos (sem
# document_template_id) seguem usando o caminho Prawn intocado.
module DocumentTemplateExtension
  extend ActiveSupport::Concern

  included do
    belongs_to :document_template, optional: true

    scope :from_template, -> { where.not(document_template_id: nil) }
    scope :legacy_pdf,    -> { where(document_template_id: nil) }

    validate :rendered_html_immutability, on: :update
  end

  # Resposta rápida sem precisar carregar o template. Usada pelo
  # Patients::PdfGenerator pra decidir Grover vs Prawn.
  def generated_from_template?
    document_template_id.present?
  end

  # Nome simbólico do renderer que vai ser usado. Útil pra logging,
  # métricas e UI.
  def renderer_kind
    generated_from_template? ? :grover : :prawn
  end

  private

  # rendered_html é a fonte da verdade do documento renderizado, com
  # variáveis JÁ resolvidas no momento da geração. Permitir UPDATE quebraria
  # a garantia de integridade (paciente assinou conteúdo X mas DB diz Y).
  #
  # Aceitamos preenchimento na criação (`update!` chamado pelo PdfGenerator
  # logo após o create do record); o que bloqueamos é mudar uma vez que já
  # foi escrito.
  def rendered_html_immutability
    return unless will_save_change_to_rendered_html?
    return if rendered_html_was.blank?

    errors.add(:rendered_html, 'cannot be modified after initial generation')
  end
end
