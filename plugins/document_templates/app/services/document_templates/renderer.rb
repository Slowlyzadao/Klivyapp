# frozen_string_literal: true

module DocumentTemplates
  # Renderiza um documento ProseMirror (JSON do TipTap) em HTML pronto pra
  # impressão via Grover (Chromium headless).
  #
  # Walk recursivo na árvore. Cada tipo de nó vira um método `render_<type>`.
  # Nós tipo `variable` consultam o Resolver pra puxar o valor real do
  # paciente/clínica/profissional e aplicam o formatter (CPF, data, etc.).
  #
  # **Segurança**: todo texto livre é escapado com ERB::Util.html_escape antes
  # de entrar no HTML. Variáveis também (exceto formatter `:image_tag` que
  # gera tag controlada com URL escapada).
  #
  # Saída: string HTML COMPLETA (`<!DOCTYPE html>...</html>`) — Grover consome
  # direto. Layout é gerenciado pelo template ERB `pdf_layout.html.erb`.
  class Renderer
    # Limite de profundidade do walk recursivo. content_json é validado pra
    # <500KB no modelo, mas isso não impede aninhamento patológico (ex.:
    # milhares de blockquotes/listas aninhadas cabem em <500KB). Sem teto, o
    # render recursivo estoura a pilha (SystemStackError) e derruba a request.
    # 100 níveis é folgado pra documentos reais (contratos/consentimentos).
    MAX_NODE_DEPTH = 100

    def initialize(template:, resolver:)
      @template = template
      @resolver = resolver
      @depth = 0
    end

    def render
      body_html = render_node(@template.content_json).to_s
      wrap_with_layout(body_html)
    end

    # Renderiza um preview HTML simplificado do content_json — usado nos
    # cards de listagem (TemplateCard). Sem variáveis resolvidas (mostra
    # fallback ou nome em itálico), sem imagens, sem links, sem styles
    # inline. Truncado por contagem de caracteres pra ficar leve.
    #
    # Retorna string HTML safe (já escapada). Frontend usa v-html dentro
    # de um container que limita visual via CSS.
    def self.preview_html(content_json, max_chars: 400)
      return '' if content_json.blank?

      builder = PreviewBuilder.new(max_chars: max_chars)
      builder.render(content_json)
      builder.result
    end

    # Walker dedicado pra preview. Mantém estado de contagem de chars
    # pra parar mid-render quando atinge o limite.
    class PreviewBuilder
      INLINE_MARKS_SUPPORTED = %w[bold italic underline strike].freeze

      def initialize(max_chars:)
        @max_chars = max_chars
        @char_count = 0
        @output = +''
        @done = false
      end

      def result
        @output
      end

      def render(node)
        return if @done || node.nil?
        return node.each { |n| render(n) } if node.is_a?(Array)
        return unless node.is_a?(Hash)

        case node['type']
        when 'doc'         then render_children(node)
        when 'heading'     then wrap_heading(node)
        when 'paragraph'   then wrap('p') { render_children(node) }
        when 'bulletList'  then wrap('ul') { render_children(node) }
        when 'orderedList' then wrap('ol') { render_children(node) }
        when 'listItem'    then wrap('li') { render_children(node) }
        when 'blockquote'  then wrap('blockquote') { render_children(node) }
        when 'text'        then emit_text(node['text'].to_s, node['marks'])
        when 'variable'    then emit_variable(node)
        when 'hardBreak'   then @output << '<br>'
        else                    render_children(node)
        end
      end

      private

      def render_children(node)
        Array(node['content']).each do |child|
          render(child)
          break if @done
        end
      end

      def wrap_heading(node)
        # clamp(1,4) acompanha os níveis do editor (StarterKit levels [1-4]).
        level = (node.dig('attrs', 'level') || 1).to_i.clamp(1, 4)
        wrap("h#{level}") { render_children(node) }
      end

      def wrap(tag)
        return if @done

        @output << "<#{tag}>"
        yield
        @output << "</#{tag}>"
      end

      def emit_text(text, marks)
        return if @done || text.empty?

        remaining = @max_chars - @char_count
        if text.length >= remaining
          text = text[0, [remaining, 0].max].to_s + '…'
          @done = true
        end

        html = ERB::Util.html_escape(text)
        Array(marks).each do |mark|
          next unless INLINE_MARKS_SUPPORTED.include?(mark['type'])

          tag = mark['type'] == 'strike' ? 's' : mark_tag(mark['type'])
          html = "<#{tag}>#{html}</#{tag}>"
        end

        @char_count += text.length
        @output << html
      end

      # Variável: renderiza o fallback (se houver) ou o nome da var em
      # itálico cinza — indica visualmente que ali entra dado dinâmico.
      def emit_variable(node)
        fallback = node.dig('attrs', 'fallback').to_s
        key = node.dig('attrs', 'key').to_s
        label = fallback.presence || "[#{key}]"
        emit_text(label, [{ 'type' => 'italic' }])
      end

      def mark_tag(type)
        { 'bold' => 'strong', 'italic' => 'em', 'underline' => 'u' }[type]
      end
    end

    private

    # Pode receber Hash (nó), Array (lista de filhos) ou nil.
    def render_node(node)
      return '' if node.nil?
      return node.map { |n| render_node(n) }.join if node.is_a?(Array)
      return '' unless node.is_a?(Hash)

      type = node['type']
      case type
      when 'doc'         then render_children(node)
      when 'paragraph'   then render_paragraph(node)
      when 'heading'     then render_heading(node)
      when 'bulletList'  then "<ul>#{render_children(node)}</ul>"
      when 'orderedList' then "<ol>#{render_children(node)}</ol>"
      when 'listItem'    then "<li>#{render_children(node)}</li>"
      when 'blockquote'  then "<blockquote>#{render_children(node)}</blockquote>"
      when 'codeBlock'   then "<pre><code>#{ERB::Util.html_escape(node_text(node))}</code></pre>"
      when 'horizontalRule' then '<hr />'
      when 'hardBreak'   then '<br />'
      when 'text'        then render_text(node)
      when 'variable'    then render_variable(node)
      when 'table'       then "<table>#{render_children(node)}</table>"
      when 'tableRow'    then "<tr>#{render_children(node)}</tr>"
      when 'tableCell'   then "<td>#{render_children(node)}</td>"
      when 'tableHeader' then "<th>#{render_children(node)}</th>"
      when 'image'       then render_image(node)
      when 'pageBreak'   then render_page_break
      else
        # Tipos desconhecidos: renderiza só o conteúdo dos filhos pra não
        # perder texto. Evita "sumir" conteúdo quando uma extensão TipTap
        # nova é usada e a gente ainda não mapeou.
        render_children(node)
      end
    end

    # Quebra de página forçada no PDF. Chromium (via Grover) honra
    # break-after: page; / page-break-after: always.
    def render_page_break
      '<div style="page-break-after: always; break-after: page;"></div>'
    end

    def render_children(node)
      # Guarda de profundidade: cada descida em filhos incrementa @depth.
      # Acima do teto, corta o ramo (devolve vazio) em vez de recursar e
      # estourar a pilha. Single-thread por render → contador de instância ok.
      @depth += 1
      return '' if @depth > MAX_NODE_DEPTH

      Array(node['content']).map { |child| render_node(child) }.join
    ensure
      @depth -= 1
    end

    def render_paragraph(node)
      style = paragraph_style(node)
      attrs = style.present? ? %( style="#{style}") : ''
      inner = render_children(node)
      # Parágrafo vazio vira <br> pra preservar espaço vertical no PDF.
      inner = '<br />' if inner.empty?
      "<p#{attrs}>#{inner}</p>"
    end

    def render_heading(node)
      level = (node.dig('attrs', 'level') || 1).to_i.clamp(1, 6)
      style = paragraph_style(node)
      attrs = style.present? ? %( style="#{style}") : ''
      "<h#{level}#{attrs}>#{render_children(node)}</h#{level}>"
    end

    def render_text(node)
      escaped = ERB::Util.html_escape(node['text'].to_s)
      apply_marks(escaped, node['marks'])
    end

    def render_variable(node)
      key = node.dig('attrs', 'key')
      fallback = node.dig('attrs', 'fallback')

      value = @resolver.resolve(key, fallback: fallback)

      # Formatter :image_tag já retorna HTML pronto (com URL escapada). Pra
      # tudo mais, escapa pra evitar XSS via dado de paciente/clínica.
      definition = Catalog.find(key)
      if definition&.formatter == :image_tag
        value.to_s
      else
        ERB::Util.html_escape(value.to_s)
      end
    end

    def render_image(node)
      src = node.dig('attrs', 'src').to_s.strip
      return '' if src.blank?
      # Mesmo allowlist dos links: bloqueia javascript:/data:/vbscript: antes
      # de chegar no PDF. allowBase64:false no editor reforça no front.
      return '' unless safe_href?(src)

      alt = ERB::Util.html_escape(node.dig('attrs', 'alt').to_s)
      safe_src = ERB::Util.html_escape(src)
      %(<img src="#{safe_src}" alt="#{alt}" />)
    end

    # Aplica marks do TipTap (bold, italic, underline, strike, link, code,
    # textStyle com color/fontFamily). Wraps em ordem estável — bold mais
    # interno pra evitar visualizações estranhas.
    def apply_marks(html, marks)
      return html if marks.blank?

      marks.each do |mark|
        case mark['type']
        when 'bold'        then html = "<strong>#{html}</strong>"
        when 'italic'      then html = "<em>#{html}</em>"
        when 'underline'   then html = "<u>#{html}</u>"
        when 'strike'      then html = "<s>#{html}</s>"
        when 'superscript' then html = "<sup>#{html}</sup>"
        when 'subscript'   then html = "<sub>#{html}</sub>"
        when 'code'        then html = "<code>#{html}</code>"
        when 'highlight'   then html = render_highlight_mark(html, mark)
        when 'link'        then html = render_link_mark(html, mark)
        when 'textStyle'   then html = render_text_style_mark(html, mark)
        end
      end
      html
    end

    # Realce (highlight). Com cor → <mark style="background-color: X">;
    # sem cor (ou cor inválida) → <mark> simples (amarelo default do browser).
    def render_highlight_mark(html, mark)
      color = sanitize_color(mark.dig('attrs', 'color'))
      return %(<mark style="background-color: #{color}">#{html}</mark>) if color.present?

      "<mark>#{html}</mark>"
    end

    # Schemes aceitos em links. Tudo fora da lista é DESCARTADO — defesa
    # contra `javascript:`, `data:`, `vbscript:` que poderiam virar XSS
    # quando o PDF é aberto em viewers que executam JS embarcado.
    SAFE_LINK_SCHEMES = %w[http https mailto tel].freeze

    def render_link_mark(html, mark)
      raw_href = mark.dig('attrs', 'href').to_s.strip
      return html if raw_href.blank?
      return html unless safe_href?(raw_href)

      href = ERB::Util.html_escape(raw_href)
      target = mark.dig('attrs', 'target') == '_blank' ? ' target="_blank" rel="noopener"' : ''
      %(<a href="#{href}"#{target}>#{html}</a>)
    end

    # Aceita: URLs com scheme http/https/mailto/tel + paths relativos
    # (começando com `/` ou `#`). Rejeita: javascript:, data:, vbscript:.
    def safe_href?(href)
      return true if href.start_with?('/', '#')
      return false unless href.include?(':')

      scheme = href.split(':', 2).first&.downcase
      SAFE_LINK_SCHEMES.include?(scheme)
    end

    def render_text_style_mark(html, mark)
      styles = []
      color = sanitize_color(mark.dig('attrs', 'color'))
      font  = sanitize_font_family(mark.dig('attrs', 'fontFamily'))
      size  = sanitize_font_size(mark.dig('attrs', 'fontSize'))

      styles << "color: #{color}" if color.present?
      styles << "font-family: #{font}" if font.present?
      styles << "font-size: #{size}" if size.present?
      return html if styles.empty?

      %(<span style="#{styles.join('; ')}">#{html}</span>)
    end

    # Passo do recuo em `em` — DEVE bater com Indent.js (renderHTML lvl*2 em).
    INDENT_STEP_EM = 2
    MAX_INDENT_LEVEL = 8

    # Acumula text-align + line-height + indent (margin-left) no mesmo nó.
    # text-align fica PRIMEIRO pra minimizar churn nos snapshots de spec.
    # Retorna String (mantém os guards `style.present?` em render_paragraph/
    # render_heading intactos).
    def paragraph_style(node)
      styles = []

      align = node.dig('attrs', 'textAlign')
      styles << "text-align: #{align}" if %w[left center right justify].include?(align)

      lh = sanitize_line_height(node.dig('attrs', 'lineHeight'))
      styles << "line-height: #{lh}" if lh.present?

      level = node.dig('attrs', 'indent').to_i
      if level.positive?
        level = [level, MAX_INDENT_LEVEL].min
        styles << "margin-left: #{level * INDENT_STEP_EM}em"
      end

      styles.join('; ')
    end

    # line-height aceita só número (1, 1.5) com unidade opcional (px/em/rem/%).
    # Estrito de propósito — NÃO passa pelo sanitize_css_value permissivo.
    def sanitize_line_height(value)
      raw = value.to_s.strip
      return '' unless raw.match?(/\A\d+(\.\d+)?(px|em|rem|%)?\z/)

      raw
    end

    # ── Sanitizers por propriedade (ALLOWLIST estrito, ancorado \A...\z) ──────
    # Substituem o antigo sanitize_css_value (blocklist permissivo) que não
    # filtrava `;`/`:` — isso permitia injeção de declarações CSS extras
    # (esconder cláusula com display:none, overlay branco position:fixed) e
    # bypass de url() via escape CSS (\75 rl(...)) → SSRF no Chromium do PDF.
    # Aqui, valor que não casa o grammar da propriedade é DESCARTADO (a
    # declaração some), nunca "melhor-esforço".

    # Cor: #hex (3-8 dígitos) | rgb/rgba/hsl/hsla numéricos | nome simples.
    # Rejeita qualquer coisa com ;, :, \, ou parênteses fora de rgb/hsl.
    def sanitize_color(value)
      raw = value.to_s.strip
      return '' if raw.empty?
      return raw if raw.match?(/\A#[0-9a-fA-F]{3,8}\z/)
      return raw if raw.match?(/\A(?:rgb|rgba|hsl|hsla)\(\s*[0-9.,%\s]+\)\z/i)
      return raw if raw.match?(/\A[a-zA-Z]+\z/)

      ''
    end

    # Font-family: letras/dígitos/espaço/vírgula/aspas/hífen. Sem ;, :, \, ().
    def sanitize_font_family(value)
      raw = value.to_s.strip
      return '' if raw.empty?
      return '' unless raw.match?(/\A[A-Za-z0-9 ,'"\-]+\z/)

      raw
    end

    # Font-size: número + unidade obrigatória (o editor sempre manda px).
    def sanitize_font_size(value)
      raw = value.to_s.strip
      return '' unless raw.match?(/\A\d+(\.\d+)?(px|pt|em|rem|%)\z/)

      raw
    end

    # Concatena todo o texto plano de um nó (usado por codeBlock).
    def node_text(node)
      Array(node['content']).map do |child|
        child['type'] == 'text' ? child['text'].to_s : node_text(child)
      end.join
    end

    # Envelopa o HTML do body com header/footer/CSS. Carrega o ERB direto
    # do disco e renderiza inline — evita configurar view_paths no engine
    # e mantém o Renderer independente de ActionController.
    def wrap_with_layout(body_html)
      template_path = self.class.layout_template_path
      erb = ERB.new(File.read(template_path), trim_mode: '-')

      clinic_reader       = Readers::ClinicReader.new(@resolver.clinic)
      professional_reader = Readers::ProfessionalReader.new(@resolver.professional)
      patient             = @resolver.patient
      now                 = @resolver.now
      template            = @template
      body_html           = body_html # captured by binding

      erb.result(binding)
    end

    def self.layout_template_path
      @layout_template_path ||= File.expand_path(
        '../../views/document_templates/pdf_layout.html.erb',
        __dir__
      )
    end
  end
end
