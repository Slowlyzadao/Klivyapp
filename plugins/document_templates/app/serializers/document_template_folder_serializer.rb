# Serializa DocumentTemplateFolder pro JSON da API.
#
# Sem gem dedicada (telemed segue mesmo padrão) — função pura que retorna
# Hash. Mantém o controller enxuto.
class DocumentTemplateFolderSerializer
  def initialize(folder)
    @folder = folder
  end

  def as_json(*)
    {
      id: @folder.id,
      account_id: @folder.account_id,
      parent_id: @folder.parent_id,
      name: @folder.name,
      position: @folder.position,
      color: @folder.color,
      icon: @folder.icon,
      templates_count: @folder.templates.respond_to?(:count) ? @folder.templates.count : 0,
      created_at: @folder.created_at,
      updated_at: @folder.updated_at
    }
  end
end
