# frozen_string_literal: true

module DocumentTemplates
  module Seeds
    # DSL pra construir nós ProseMirror em Ruby — muito mais legível que
    # editar JSON puro. Usado pelos arquivos de definição de templates
    # Klivy (clinical_templates.rb, consent_templates.rb).
    #
    # Exemplo:
    #   include DocumentTemplates::Seeds::Builder
    #
    #   doc(
    #     heading(1, 'ATESTADO MÉDICO', align: 'center'),
    #     paragraph(
    #       text('Atesto que '),
    #       variable('patient.full_name'),
    #       text(', CPF '),
    #       variable('patient.cpf'),
    #       text(', encontra-se sob meus cuidados.')
    #     ),
    #     paragraph(variable('date.city_today'), align: 'right')
    #   )
    #
    # Output: hash do tipo `{ 'type' => 'doc', 'content' => [...] }` pronto
    # pra ser salvo em `DocumentTemplate.content_json`.
    module Builder
      module_function

      def doc(*content)
        { 'type' => 'doc', 'content' => content.flatten.compact }
      end

      def paragraph(*content, align: nil)
        node = { 'type' => 'paragraph', 'content' => normalize_inline(content) }
        node['attrs'] = { 'textAlign' => align } if align
        node
      end

      def heading(level, content, align: nil)
        attrs = { 'level' => Integer(level) }
        attrs['textAlign'] = align if align
        {
          'type' => 'heading',
          'attrs' => attrs,
          'content' => normalize_inline(content)
        }
      end

      def text(str, marks: nil)
        node = { 'type' => 'text', 'text' => str.to_s }
        node['marks'] = Array(marks).compact if marks && Array(marks).any?
        node
      end

      def bold(str)
        text(str, marks: [{ 'type' => 'bold' }])
      end

      def italic(str)
        text(str, marks: [{ 'type' => 'italic' }])
      end

      def variable(key, label: nil, fallback: '_______', format: nil)
        attrs = {
          'key' => key.to_s,
          'label' => label || default_label_for(key),
          'fallback' => fallback
        }
        attrs['format'] = format if format
        { 'type' => 'variable', 'attrs' => attrs }
      end

      def hard_break
        { 'type' => 'hardBreak' }
      end

      def horizontal_rule
        { 'type' => 'horizontalRule' }
      end

      def bullet_list(*items)
        { 'type' => 'bulletList', 'content' => items.flatten.map { |i| list_item(i) } }
      end

      def ordered_list(*items)
        { 'type' => 'orderedList', 'content' => items.flatten.map { |i| list_item(i) } }
      end

      # Aceita string ou array de nós inline — embrulha em parágrafo dentro
      # do listItem (estrutura ProseMirror padrão).
      def list_item(content)
        inner = content.is_a?(String) ? [text(content)] : Array(content)
        { 'type' => 'listItem', 'content' => [paragraph(*inner)] }
      end

      # Linha de assinatura: linha pontilhada + nome + caption.
      # Helper porque aparece em ~todos os templates.
      def signature_block(name_variable_key, caption_text)
        [
          paragraph(text('_______________________________'), align: 'center'),
          paragraph(variable(name_variable_key), align: 'center'),
          paragraph(italic(caption_text), align: 'center')
        ]
      end

      # Lookup no Catalog pra preencher o label do chip. Defaultando pra key
      # quando não existir (caso de variável customizada futura).
      def default_label_for(key)
        DocumentTemplates::Catalog.find(key.to_s)&.label || key.to_s
      end

      # Normaliza conteúdo inline: aceita strings, nodes, ou arrays — sempre
      # devolve flat array de nodes. Strings viram `text` nodes automaticamente.
      def normalize_inline(content)
        Array(content).flatten.compact.map do |c|
          c.is_a?(String) ? text(c) : c
        end
      end
    end
  end
end
