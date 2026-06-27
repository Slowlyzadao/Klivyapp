# frozen_string_literal: true

# Gerador genérico de documentos avulsos do paciente (atestado, receita,
# pedido de exame, declaração, relatório clínico, encaminhamento). Salva
# o PDF como `Document` via Active Storage e retorna o binário no Result.
module Patients
  class PdfGenerator < Patients::Pdf::BasePdf
    Result = Struct.new(:success?, :document, :pdf_data, :error, keyword_init: true)

    # Cor do badge centralizado no topo, por tipo de documento.
    TYPE_INTENT = {
      'atestado' => :info,
      'receita' => :success,
      'pedido_exame' => :info,
      'declaracao' => :info,
      'relatorio_clinico' => :info,
      'encaminhamento' => :warning,
      'contrato' => :info,
      'orcamento' => :success,
      'instrucao_procedimento' => :warning,
      'questionario' => :info,
      'outro' => :info
    }.freeze

    # Tipos onde o paciente também assina (além do profissional).
    # Padrão: só profissional. Acrescentar aqui só quando faz sentido legal/operacional.
    TYPES_WITH_PATIENT_SIGNATURE = %w[contrato instrucao_procedimento orcamento].freeze

    def self.call(**args)
      new(**args).run
    end

    def initialize(patient:, document_type:, variables: {}, generated_by: nil, title: nil, form_template_id: nil, document_template_id: nil, inputs: {})
      @patient          = patient
      @account          = patient.account
      @document_type    = document_type
      @variables        = variables || {}
      @generated_by     = generated_by
      @title            = title || default_title(document_type)
      @form_template_id = form_template_id
      # Fase document-editor: se presente, `run` delega pro
      # DocumentTemplates::PdfGenerator (Grover) em vez do Prawn legado.
      @document_template_id = document_template_id
      # Campos de preenchimento (input.*) digitados no modal de geração.
      @inputs = inputs || {}
    end

    def run
      # Caminho novo (editor visual + Grover): com template, delega.
      return delegate_to_template_engine if @document_template_id.present?

      pdf_data = call

      document = save_document(pdf_data)

      Result.new(success?: true, document: document, pdf_data: pdf_data, error: nil)
    rescue StandardError => e
      Rails.logger.error("[PdfGenerator] Erro ao gerar PDF: #{e.message}")
      Result.new(success?: false, document: nil, pdf_data: nil, error: e.message)
    end

    # Caminho novo (Grover). Carrega o template escopado pela account
    # corrente — se a clínica não tiver acesso (não é dela nem é Klivy
    # global), RecordNotFound vira erro tratável no Result.
    def delegate_to_template_engine
      template = ::DocumentTemplate.for_account(@account).find(@document_template_id)

      result = ::DocumentTemplates::PdfGenerator.call(
        template: template,
        patient: @patient,
        professional: @generated_by,
        clinic: @account,
        title: @title,
        inputs: @inputs
      )

      Result.new(
        success?: result.success?,
        document: result.document,
        pdf_data: result.pdf_data,
        error: result.error
      )
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn("[PdfGenerator] template_id=#{@document_template_id} inacessível: #{e.message}")
      Result.new(success?: false, document: nil, pdf_data: nil, error: 'Template não encontrado ou sem acesso')
    end

    private

    attr_reader :patient, :account, :document_type, :variables, :generated_by, :title, :form_template_id

    def header_account_name
      account&.name.to_s.presence || brand_name
    end

    def header_subtitle
      title.to_s
    end

    # Ordem visual: badge (tipo do doc) → Dados do Paciente → Conteúdo →
    # Observações (se houver) → Assinaturas. Igual ao TreatmentPlanPdfGenerator
    # pra manter coerência entre PDFs.
    def build
      draw_centered_badge(title, intent: type_intent)
      draw_patient_card
      draw_body
      draw_observations
      draw_signature_line
    end

    # Renderiza o campo livre `observacoes` (vem do form pra qualquer tipo de
    # documento) como uma seção dedicada. Antes esse texto era enviado mas
    # nunca aparecia no PDF — bug silencioso.
    def draw_observations
      observations = var('observacoes', 'observations')
      return if observations.blank?

      draw_section_title('Observações')
      draw_highlight_block(label: 'Informações Complementares', content: observations.to_s)
    end

    def type_intent
      TYPE_INTENT.fetch(document_type, :info)
    end

    def draw_patient_card
      draw_section_title('Dados do Paciente')

      draw_kv_grid(
        [
          ['Nome', patient.name.to_s],
          ['CPF', fmt_cpf(patient.cpf)],
          ['Data de Nascimento', patient.birthdate&.strftime('%d/%m/%Y') || 'Não informada'],
          ['Data de Emissão', Date.current.strftime('%d/%m/%Y')]
        ]
      )

      address = format_address(patient.address)
      draw_highlight_block(label: 'Endereço', content: address) if address.present?
    end

    def format_address(address)
      return nil if address.blank? || !address.is_a?(Hash)

      parts = []
      parts << "#{address['street']}, #{address['number'].presence || 'S/N'}" if address['street'].present?
      parts << address['complement'] if address['complement'].present?
      parts << "- #{address['neighborhood']}" if address['neighborhood'].present?
      parts << "- #{address['city']}/#{address['state']}" if address['city'].present?
      parts << "| CEP: #{address['zip_code']}" if address['zip_code'].present?

      parts.join(' ')
    end

    def draw_body
      case document_type
      when 'atestado'           then draw_atestado
      when 'receita'            then draw_receita
      when 'pedido_exame'       then draw_pedido_exame
      when 'declaracao'         then draw_declaracao
      when 'relatorio_clinico'  then draw_relatorio_clinico
      when 'encaminhamento'     then draw_encaminhamento
      else                           draw_generic
      end
    end

    def draw_atestado
      duration_days = var('dias_afastamento', 'duration_days')
      cid           = var('cid')
      reason        = var('reason').presence || 'Para os devidos fins'

      draw_section_title('Conteúdo do Atestado')

      pdf.font('Helvetica') do
        pdf.text(
          'Atesto que o(a) paciente acima identificado(a) encontra-se sob meus cuidados ' \
          'profissionais, necessitando de afastamento de suas atividades por um período de ' \
          "#{duration_days || '___'} (#{days_in_full(duration_days)}) dia(s) a partir desta data.",
          size: 11, leading: 3
        )
      end
      pdf.move_down 10

      draw_highlight_block(label: 'CID-10', content: cid.to_s) if cid.present?

      pdf.font('Helvetica') do
        pdf.text reason.to_s, size: 11
      end
      pdf.move_down 20
    end

    # Receita atual do form é texto livre (`medicamentos`, `posologia`).
    # Mantemos suporte ao formato estruturado (`medications` = array) caso
    # alguma rota futura envie como tabela.
    def draw_receita
      medications = var('medications')
      medicamentos_text = var('medicamentos')
      posologia_text    = var('posologia')

      draw_section_title('Prescrição Médica')

      if medications.is_a?(Array) && medications.any?
        rows = medications.map.with_index(1) do |med, idx|
          name = med['name'] || med[:name] || '—'
          dosage = med['dosage'] || med[:dosage] || '—'
          instructions = med['instructions'] || med[:instructions] || '—'
          [idx.to_s, name.to_s, dosage.to_s, instructions.to_s]
        end
        draw_data_table(['#', 'Medicamento', 'Posologia', 'Orientações'], rows, col_widths: [30, 160, 130, 175])
      elsif medicamentos_text.present? || posologia_text.present?
        draw_highlight_block(label: 'Medicamentos', content: medicamentos_text.to_s) if medicamentos_text.present?
        draw_highlight_block(label: 'Posologia', content: posologia_text.to_s) if posologia_text.present?
      else
        draw_empty('Nenhum medicamento informado.')
      end
      pdf.move_down 16
    end

    def draw_pedido_exame
      exams_array = var('exams')
      exams_text  = var('exames_solicitados')
      indication  = var('clinical_indication')

      draw_section_title('Pedido de Exames')

      draw_highlight_block(label: 'Indicação Clínica', content: indication.to_s) if indication.present?

      pdf.font('Helvetica', style: :bold) { pdf.text 'Solicito os seguintes exames:', size: 10 }
      pdf.move_down 6

      bullets = if exams_array.is_a?(Array) && exams_array.any?
                  exams_array.map(&:to_s)
                elsif exams_text.present?
                  exams_text.to_s.split(/[\n,;]+/).map(&:strip).reject(&:empty?)
                else
                  []
                end

      if bullets.any?
        bullets.each { |exam| draw_bullet(exam) }
      else
        draw_empty('Nenhum exame informado.')
      end
      pdf.move_down 12
    end

    def draw_encaminhamento
      destination = var('encaminhado_para', 'destination')
      specialty   = var('especialidade', 'specialty')
      reason      = var('reason')

      draw_section_title('Encaminhamento')

      pdf.font('Helvetica') { pdf.text 'Encaminho o(a) paciente acima identificado(a) para atendimento especializado.', size: 11 }
      pdf.move_down 10

      grid = []
      grid << ['Especialidade', specialty.to_s.presence || '—']
      grid << ['Destino', destination.to_s] if destination.present?
      draw_kv_grid(grid)

      draw_highlight_block(label: 'Motivo do Encaminhamento', content: reason.to_s) if reason.present?
    end

    def draw_declaracao
      content = free_content.presence ||
                'Declaro para os devidos fins que o(a) paciente encontra-se em acompanhamento nesta clínica.'

      draw_section_title('Declaração')
      pdf.font('Helvetica') { pdf.text content.to_s, size: 11, leading: 3 }
      pdf.move_down 20
    end

    def draw_relatorio_clinico
      draw_section_title('Relatório Clínico')
      content = free_content.presence || '—'
      pdf.font('Helvetica') { pdf.text content.to_s, size: 11, leading: 3 }
      pdf.move_down 20
    end

    def draw_generic
      content = free_content.to_s
      draw_section_title('Conteúdo')
      if content.present?
        pdf.font('Helvetica') { pdf.text content, size: 11, leading: 3 }
        pdf.move_down 20
      else
        draw_empty('Sem conteúdo informado.')
      end
    end

    # Form usa `conteudo_livre` (frontend) → mapeado para `conteudo` no payload.
    # Aceitamos `content` também caso futuras integrações usem o nome inglês.
    def free_content
      var('conteudo', 'conteudo_livre', 'content')
    end

    # Bloco de assinaturas no rodapé. Para tipos legais/operacionais
    # (TYPES_WITH_PATIENT_SIGNATURE) renderiza paciente à esquerda + profissional
    # à direita. Para os demais (atestado, receita, pedido_exame, etc.) só
    # profissional, centralizado.
    def draw_signature_line
      ensure_space(80)
      pdf.move_down 10

      professional_name = var('professional_name').presence || generated_by&.name || 'Profissional Responsável'
      crm = var('crm')
      prof_caption = if crm.present?
                       "Assinado eletronicamente em #{fmt_datetime(Time.current)} · CRM/CRO/CRF: #{crm}"
                     else
                       "Assinado eletronicamente em #{fmt_datetime(Time.current)}"
                     end

      if TYPES_WITH_PATIENT_SIGNATURE.include?(document_type)
        draw_signatures(
          left:  { name: patient.name, caption: 'Assinatura do Paciente' },
          right: { name: professional_name, caption: prof_caption, caption_italic: true }
        )
      else
        draw_signatures(
          left: { name: professional_name, caption: prof_caption, caption_italic: true }
        )
      end
    end

    # Lê variável aceitando múltiplas chaves (PT/EN). Retorna o primeiro valor
    # presente — útil porque o frontend usa nomes em português (`dias_afastamento`,
    # `medicamentos`) e versões antigas/futuras da API podem usar inglês
    # (`duration_days`, `medications`).
    def var(*keys)
      keys.each do |key|
        value = variables[key.to_s] || variables[key.to_sym]
        return value if value.respond_to?(:present?) ? value.present? : !value.nil?
      end
      nil
    end

    def save_document(pdf_data)
      doc = Document.new(
        patient: patient,
        account: account,
        generated_by: generated_by,
        form_template_id: form_template_id,
        document_type: document_type,
        title: title,
        is_generated: true,
        status: 'gerado',
        variables: variables
      )

      doc.file.attach(
        io: StringIO.new(pdf_data),
        filename: "#{document_type}-#{patient.id}-v#{doc.version || 1}.pdf",
        content_type: 'application/pdf'
      )

      doc.save!
      doc
    end

    def default_title(type)
      {
        'atestado' => 'Atestado Médico',
        'receita' => 'Receita Médica',
        'pedido_exame' => 'Pedido de Exame',
        'declaracao' => 'Declaração',
        'relatorio_clinico' => 'Relatório Clínico',
        'encaminhamento' => 'Encaminhamento',
        'instrucao_procedimento' => 'Instruções de Procedimento',
        'contrato' => 'Contrato de Prestação de Serviços',
        'orcamento' => 'Orçamento'
      }.fetch(type, type.to_s.humanize)
    end

    def days_in_full(days)
      return 'indefinido' if days.blank? || days.to_i <= 0

      case days.to_i
      when 1 then 'um'
      when 2 then 'dois'
      when 3 then 'três'
      when 4 then 'quatro'
      when 5 then 'cinco'
      when 6 then 'seis'
      when 7 then 'sete'
      else days.to_s
      end
    end
  end
end
