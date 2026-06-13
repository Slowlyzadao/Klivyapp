# frozen_string_literal: true

module DocumentTemplates
  module Variables
    # Variáveis de PREENCHIMENTO (categoria "Campos de preenchimento").
    #
    # Diferente das demais categorias (paciente/clínica/profissional/data), que
    # resolvem do CADASTRO, estas são dados de INSTÂNCIA do documento — não
    # existem em lugar nenhum até o operador digitar na hora de gerar. Ex.: num
    # atestado, "Dias de afastamento" e "CID" mudam a cada emissão.
    #
    # Como funciona: a chave começa com `input.`; o Resolver NÃO usa reader pra
    # elas — pega o valor do mapa `inputs` que o modal "Gerar Documento" coleta
    # (introspectando quais campos `input.*` o modelo usa) e envia na geração.
    # O autor do modelo insere esses chips onde o valor deve aparecer.
    module InputDefinitions
      LIST = [
        { key: 'input.dias_afastamento', label: 'Dias de afastamento', example: '2' },
        { key: 'input.cid',              label: 'CID',                  example: 'M54.5' },
        { key: 'input.data',             label: 'Data',                 example: '04/06/2026' },
        { key: 'input.periodo',          label: 'Período',              example: 'manhã' },
        { key: 'input.horario',          label: 'Horário',              example: '14:00' },
        { key: 'input.valor',            label: 'Valor',                example: 'R$ 150,00' },
        { key: 'input.quantidade',       label: 'Quantidade',           example: '3' },
        { key: 'input.medicamento',      label: 'Medicamento',          example: 'Dipirona 500mg' },
        { key: 'input.observacao',       label: 'Observação',           example: 'Repouso relativo' },
        { key: 'input.texto_livre',      label: 'Texto livre',          example: '—' }
      ].map { |attrs| DocumentTemplates::Variable.new(category: 'Campos de preenchimento', **attrs) }.freeze
    end
  end
end
