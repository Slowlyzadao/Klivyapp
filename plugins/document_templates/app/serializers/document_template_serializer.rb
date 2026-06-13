# Serializa DocumentTemplate pro JSON da API.
#
# `as_json(include_content: false)` — versão compacta pra listagem (sem o
# content_json gigante).
# `as_json(include_content: true)`  — versão completa, usada no editor.
class DocumentTemplateSerializer
  def initialize(template)
    @template = template
  end

  def as_json(include_content: false, **)
    base = {
      id: @template.id,
      account_id: @template.account_id,
      folder_id: @template.folder_id,
      name: @template.name,
      description: @template.description,
      document_type: @template.document_type,
      family: @template.family,
      source: @template.source,
      status: @template.status,
      version: @template.version,
      paper_size: @template.paper_size,
      orientation: @template.orientation,
      created_by_user_id: @template.created_by_user_id,
      source_template_id: @template.source_template_id,
      is_klivy: @template.klivy?,
      is_cloned: @template.cloned?,
      archived_at: @template.archived_at,
      created_at: @template.created_at,
      updated_at: @template.updated_at,
      # Preview HTML simplificado (texto real, ~400 chars, sem variáveis
      # resolvidas) — usado nos cards de listagem.
      preview_html: DocumentTemplates::Renderer.preview_html(@template.content_json, max_chars: 400)
    }

    base[:content_json] = @template.content_json if include_content
    base
  end
end
