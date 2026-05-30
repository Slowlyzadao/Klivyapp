# frozen_string_literal: true

module DocumentTemplates
  module Variables
    # Variáveis da categoria PACIENTE.
    #
    # Mapeamento com schema real do Patient (auditado 2026-05-27):
    #   - Patient.birthdate (não birth_date)
    #   - Patient.address (JSONB) com chaves: street, number, complement,
    #     neighborhood, city, state, zip
    #   - Patient.guardian (JSONB) com nome/cpf/rg quando has_guardian=true
    #   - patient.full_name é alias pra patient.name
    module PatientDefinitions
      LIST = [
        { key: 'patient.full_name',     label: 'Nome completo',           example: 'Maria Silva Santos' },
        { key: 'patient.first_name',    label: 'Primeiro nome',           example: 'Maria' },
        { key: 'patient.social_name',   label: 'Nome social',             example: 'Maria' },
        { key: 'patient.cpf',           label: 'CPF',                     example: '123.456.789-00', formatter: :cpf },
        { key: 'patient.rg',            label: 'RG',                      example: '12.345.678-9' },
        { key: 'patient.birthdate',     label: 'Data de nascimento',      example: '15/03/1985', formatter: :date_short },
        { key: 'patient.birthdate_long', label: 'Data de nasc. por extenso', example: '15 de março de 1985', formatter: :date_long },
        { key: 'patient.age',           label: 'Idade',                   example: '39 anos', formatter: :age },
        { key: 'patient.sex',           label: 'Sexo',                    example: 'Feminino' },
        { key: 'patient.marital_status', label: 'Estado civil',           example: 'Casado(a)' },
        { key: 'patient.phone',         label: 'Telefone',                example: '(11) 98765-4321', formatter: :phone },
        { key: 'patient.email',         label: 'E-mail',                  example: 'maria@email.com' },

        # Endereço — composto do JSONB `address`.
        { key: 'patient.address_full',         label: 'Endereço completo',  example: 'Rua das Flores, 100, Ap 5, Vila Y, São Paulo-SP, 01000-000' },
        { key: 'patient.address_street',       label: 'Logradouro',         example: 'Rua das Flores, 100' },
        { key: 'patient.address_complement',   label: 'Complemento',        example: 'Ap 5, Bl A' },
        { key: 'patient.address_neighborhood', label: 'Bairro',             example: 'Vila Mariana' },
        { key: 'patient.address_city',         label: 'Cidade',             example: 'São Paulo' },
        { key: 'patient.address_state',        label: 'Estado (UF)',        example: 'SP' },
        { key: 'patient.address_zip',          label: 'CEP',                example: '01000-000', formatter: :cep },

        # Responsável — do JSONB `guardian` (preenchido quando has_guardian=true).
        # Aparece nos templates "consentimento_menor" e contratos pra menores.
        { key: 'patient.guardian_name', label: 'Nome do responsável',     example: 'José Silva' },
        { key: 'patient.guardian_cpf',  label: 'CPF do responsável',      example: '987.654.321-00', formatter: :cpf },
        { key: 'patient.guardian_rg',   label: 'RG do responsável',       example: '12.345.678-9' },

        { key: 'patient.medical_record_id', label: 'Nº do prontuário',    example: '1234' }
      ].map { |attrs| DocumentTemplates::Variable.new(category: 'Paciente', **attrs) }.freeze
    end
  end
end
