# 04 — Backend (Rails)

## 4.1 Gems a adicionar

```ruby
# Gemfile (raiz do projeto)
gem 'grover', '~> 2.0'   # HTML → PDF via Chromium headless
```

Não há outra dependência nova de produção. ProseMirror não tem gem em Ruby — validação do JSON é manual ou com `json-schema`.

### Infra do Grover

O Grover depende de **Node.js + Puppeteer + Chromium** no servidor.

```bash
# Em ambiente dev (macOS): já vem com node, mas precisa de puppeteer
yarn add -D puppeteer

# Em produção (Dockerfile do Klivy):
# - Adicionar chromium ao apt-get install
# - Adicionar puppeteer ao package.json
# - Variável de ambiente PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
```

Documentação completa de infra em [10-pontos-de-atencao.md](10-pontos-de-atencao.md).

## 4.2 Plugin: estrutura de arquivos

```
plugins/document_templates/
├── lib/
│   ├── document_templates.rb
│   └── document_templates/
│       ├── engine.rb
│       └── version.rb
├── app/
│   ├── models/
│   │   ├── document_template.rb
│   │   ├── document_template_folder.rb
│   │   └── concerns/
│   │       └── document_template_extension.rb
│   ├── controllers/
│   │   └── api/v1/accounts/
│   │       ├── document_templates_controller.rb
│   │       ├── document_template_folders_controller.rb
│   │       └── document_template_variables_controller.rb
│   ├── services/
│   │   └── document_templates/
│   │       ├── catalog.rb
│   │       ├── resolver.rb
│   │       ├── renderer.rb
│   │       ├── pdf_generator.rb
│   │       ├── clone_klivy_template.rb
│   │       └── seed_klivy_library.rb
│   ├── jobs/
│   │   └── document_templates/
│   │       └── generate_pdf_job.rb
│   ├── policies/
│   │   ├── document_template_policy.rb
│   │   └── document_template_folder_policy.rb
│   └── serializers/
│       ├── document_template_serializer.rb
│       └── document_template_folder_serializer.rb
└── config/
    └── routes.rb
```

## 4.3 Rotas

```ruby
# plugins/document_templates/config/routes.rb
Rails.application.routes.draw do
  scope module: 'api', defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          resources :document_template_folders
          resources :document_templates do
            collection do
              get :variables   # GET .../document_templates/variables
              get :klivy_library
            end
            member do
              post :duplicate
              post :clone_to_account   # quando source='klivy' → clona pra account
              post :archive
              post :unarchive
            end
          end
        end
      end
    end
  end
end
```

## 4.4 Controllers

### `DocumentTemplatesController`

```ruby
class Api::V1::Accounts::DocumentTemplatesController < Api::V1::Accounts::BaseController
  before_action :fetch_template, only: [:show, :update, :destroy, :duplicate, :archive, :unarchive]
  before_action :authorize_admin!, only: [:create, :update, :destroy, :duplicate, :archive]

  def index
    templates = Current.account.document_templates
                       .active
                       .includes(:folder, :created_by_user)
    templates = templates.where(document_type: params[:document_type]) if params[:document_type]
    templates = templates.where(folder_id: params[:folder_id])         if params[:folder_id]
    render json: templates.map { |t| DocumentTemplateSerializer.new(t).as_json }
  end

  def klivy_library
    # Templates globais da Klivy (account_id = nil, source = 'klivy')
    templates = DocumentTemplate.where(account_id: nil, source: 'klivy', status: 'active')
    templates = templates.where(document_type: params[:document_type]) if params[:document_type]
    render json: templates.map { |t| DocumentTemplateSerializer.new(t).as_json }
  end

  def show
    render json: DocumentTemplateSerializer.new(@template).as_json(include_content: true)
  end

  def create
    template = Current.account.document_templates.build(template_params)
    template.created_by_user = Current.user
    template.source = 'clinic'
    if template.save
      render json: DocumentTemplateSerializer.new(template).as_json(include_content: true), status: :created
    else
      render json: { errors: template.errors }, status: :unprocessable_entity
    end
  end

  def update
    if @template.update(template_params)
      render json: DocumentTemplateSerializer.new(@template).as_json(include_content: true)
    else
      render json: { errors: @template.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @template.update!(archived_at: Time.current, status: 'archived')
    head :no_content
  rescue ActiveRecord::DeleteRestrictionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def duplicate
    new_template = @template.dup
    new_template.name = "#{@template.name} (cópia)"
    new_template.version = 1
    new_template.created_by_user = Current.user
    new_template.save!
    render json: DocumentTemplateSerializer.new(new_template).as_json(include_content: true), status: :created
  end

  def clone_to_account
    raise CanCan::AccessDenied unless @template.klivy?
    cloned = DocumentTemplates::CloneKlivyTemplate.new(
      klivy_template: @template,
      account: Current.account,
      user: Current.user
    ).call!
    render json: DocumentTemplateSerializer.new(cloned).as_json(include_content: true), status: :created
  end

  def variables
    render json: DocumentTemplates::Catalog.all_for_frontend
  end

  def archive
    @template.update!(status: 'archived', archived_at: Time.current)
    head :no_content
  end

  def unarchive
    @template.update!(status: 'active', archived_at: nil)
    head :no_content
  end

  private

  def fetch_template
    @template = DocumentTemplate.for_account(Current.account).find(params[:id])
  end

  def template_params
    params.require(:document_template).permit(
      :name, :description, :document_type, :folder_id,
      :paper_size, :orientation, :status,
      content_json: {}, metadata: {}
    )
  end

  def authorize_admin!
    raise CanCan::AccessDenied unless Current.user.administrator?
  end
end
```

### `DocumentTemplateFoldersController`

CRUD padrão, scope `Current.account`, autorização admin. Padrão idêntico ao acima — vamos pular o boilerplate aqui.

### `DocumentTemplateVariablesController`

Endpoint público (readonly) que retorna o catálogo de variáveis pro frontend popular o menu de inserção. Implementação ultra-curta — só chama `DocumentTemplates::Catalog.all_for_frontend`.

## 4.5 Services

### `DocumentTemplates::Catalog` — catálogo de variáveis

PORO singleton. Define todas as variáveis disponíveis com chave estável, label e formatador.

```ruby
module DocumentTemplates
  class Catalog
    Variable = Struct.new(:key, :label, :category, :example, :formatter, keyword_init: true)

    DEFINITIONS = [
      # Paciente
      Variable.new(key: 'patient.full_name', label: 'Nome completo',
                   category: 'Paciente', example: 'Maria Silva Santos'),
      Variable.new(key: 'patient.cpf', label: 'CPF',
                   category: 'Paciente', example: '123.456.789-00', formatter: :cpf),
      Variable.new(key: 'patient.rg', label: 'RG',
                   category: 'Paciente', example: '12.345.678-9'),
      Variable.new(key: 'patient.birth_date', label: 'Data de nascimento',
                   category: 'Paciente', example: '15/03/1985', formatter: :date_short),
      Variable.new(key: 'patient.age', label: 'Idade',
                   category: 'Paciente', example: '39 anos', formatter: :age),
      Variable.new(key: 'patient.phone', label: 'Telefone',
                   category: 'Paciente', example: '(11) 98765-4321', formatter: :phone),
      Variable.new(key: 'patient.email', label: 'E-mail',
                   category: 'Paciente', example: 'maria@email.com'),
      Variable.new(key: 'patient.address_full', label: 'Endereço completo',
                   category: 'Paciente', example: 'Rua X, 100, ap 5, Bairro, Cidade-SP, 01000-000'),
      Variable.new(key: 'patient.address_street', label: 'Logradouro',
                   category: 'Paciente'),
      Variable.new(key: 'patient.address_city', label: 'Cidade',
                   category: 'Paciente'),
      Variable.new(key: 'patient.address_state', label: 'Estado',
                   category: 'Paciente'),
      Variable.new(key: 'patient.address_zip', label: 'CEP',
                   category: 'Paciente', formatter: :cep),

      # Clínica
      Variable.new(key: 'clinic.name', label: 'Nome da clínica',
                   category: 'Clínica', example: 'Clínica Bem Estar'),
      Variable.new(key: 'clinic.cnpj', label: 'CNPJ',
                   category: 'Clínica', formatter: :cnpj),
      Variable.new(key: 'clinic.address_full', label: 'Endereço completo',
                   category: 'Clínica'),
      Variable.new(key: 'clinic.phone', label: 'Telefone',
                   category: 'Clínica'),
      Variable.new(key: 'clinic.email', label: 'E-mail',
                   category: 'Clínica'),
      Variable.new(key: 'clinic.logo_url', label: 'Logo (imagem)',
                   category: 'Clínica'),

      # Profissional (o User que está gerando o documento)
      Variable.new(key: 'professional.name', label: 'Nome',
                   category: 'Profissional'),
      Variable.new(key: 'professional.council_number', label: 'CRM/CRO',
                   category: 'Profissional'),
      Variable.new(key: 'professional.specialty', label: 'Especialidade',
                   category: 'Profissional'),

      # Data/Hora
      Variable.new(key: 'date.today', label: 'Data de hoje',
                   category: 'Data', example: '26/05/2026', formatter: :date_short),
      Variable.new(key: 'date.today_long', label: 'Data por extenso',
                   category: 'Data', example: '26 de maio de 2026', formatter: :date_long),
      Variable.new(key: 'date.day', label: 'Dia',
                   category: 'Data', example: '26'),
      Variable.new(key: 'date.month', label: 'Mês',
                   category: 'Data', example: 'maio'),
      Variable.new(key: 'date.year', label: 'Ano',
                   category: 'Data', example: '2026'),
      Variable.new(key: 'date.city_today', label: 'Cidade, data por extenso',
                   category: 'Data', example: 'São Paulo, 26 de maio de 2026'),
    ].freeze

    def self.find(key)
      DEFINITIONS.find { |v| v.key == key }
    end

    def self.all_for_frontend
      DEFINITIONS.map do |v|
        { key: v.key, label: v.label, category: v.category, example: v.example }
      end
    end

    def self.categories
      DEFINITIONS.map(&:category).uniq
    end
  end
end
```

Catálogo completo em [`07-catalogo-de-variaveis.md`](07-catalogo-de-variaveis.md).

### `DocumentTemplates::Resolver` — resolve variável → valor real

```ruby
module DocumentTemplates
  class Resolver
    def initialize(patient:, clinic:, professional:, now: Time.current)
      @patient = patient
      @clinic = clinic
      @professional = professional
      @now = now
    end

    def resolve(variable_key)
      raw_value = case variable_key
                  when 'patient.full_name'    then @patient.full_name
                  when 'patient.cpf'          then @patient.cpf
                  when 'patient.rg'           then @patient.rg
                  when 'patient.birth_date'   then @patient.birth_date
                  when 'patient.age'          then calculate_age(@patient.birth_date)
                  when 'patient.phone'        then @patient.phone
                  when 'patient.email'        then @patient.email
                  when 'patient.address_full' then format_address(@patient)
                  # ... demais variáveis
                  when 'clinic.name'          then @clinic.name
                  when 'clinic.cnpj'          then @clinic.cnpj
                  when 'clinic.address_full'  then format_address(@clinic)
                  when 'clinic.logo_url'      then @clinic.logo.url
                  when 'professional.name'    then @professional.name
                  when 'professional.council_number' then @professional.council_number
                  when 'date.today'           then @now.to_date
                  when 'date.today_long'      then I18n.l(@now.to_date, format: :long, locale: :'pt-BR')
                  when 'date.day'             then @now.day.to_s
                  when 'date.month'           then I18n.l(@now.to_date, format: '%B', locale: :'pt-BR')
                  when 'date.year'            then @now.year.to_s
                  when 'date.city_today'      then "#{@clinic.address_city}, #{I18n.l(@now.to_date, format: :long, locale: :'pt-BR')}"
                  end

      variable = Catalog.find(variable_key)
      apply_formatter(raw_value, variable&.formatter)
    end

    private

    def apply_formatter(value, formatter)
      return value if value.blank? || formatter.blank?
      case formatter
      when :cpf       then format_cpf(value)
      when :cnpj      then format_cnpj(value)
      when :phone     then format_phone(value)
      when :cep       then format_cep(value)
      when :date_short then I18n.l(value, format: :default, locale: :'pt-BR')
      when :date_long  then I18n.l(value, format: :long, locale: :'pt-BR')
      when :age        then "#{calculate_age(value)} anos"
      else value
      end
    end

    def calculate_age(birth_date)
      return nil if birth_date.blank?
      today = Date.current
      age = today.year - birth_date.year
      age -= 1 if today < birth_date + age.years
      age
    end

    def format_cpf(v)
      digits = v.to_s.gsub(/\D/, '')
      return v if digits.length != 11
      "#{digits[0..2]}.#{digits[3..5]}.#{digits[6..8]}-#{digits[9..10]}"
    end

    # ... outros formatadores
  end
end
```

### `DocumentTemplates::Renderer` — JSON → HTML

```ruby
module DocumentTemplates
  class Renderer
    def initialize(template:, resolver:)
      @template = template
      @resolver = resolver
    end

    def render
      html_body = render_node(@template.content_json)
      wrap_with_layout(html_body)
    end

    private

    def render_node(node)
      return '' if node.nil?
      case node['type']
      when 'doc'        then node['content'].to_a.map { |c| render_node(c) }.join
      when 'paragraph'  then "<p style=\"#{paragraph_style(node)}\">#{render_marks(node)}</p>"
      when 'heading'    then heading_tag(node)
      when 'bulletList' then "<ul>#{render_children(node)}</ul>"
      when 'orderedList' then "<ol>#{render_children(node)}</ol>"
      when 'listItem'   then "<li>#{render_children(node)}</li>"
      when 'text'       then apply_marks(node['text'], node['marks'])
      when 'variable'   then render_variable(node)
      when 'table'      then render_table(node)
      when 'hardBreak'  then '<br>'
      else ''
      end
    end

    def render_variable(node)
      key = node.dig('attrs', 'key')
      value = @resolver.resolve(key)
      value = node.dig('attrs', 'fallback') || '________' if value.blank?
      ERB::Util.html_escape(value)
    end

    def wrap_with_layout(html_body)
      ApplicationController.renderer.render(
        template: 'document_templates/pdf_layout',
        layout: false,
        assigns: {
          body_html: html_body.html_safe,
          template: @template,
          clinic: @resolver.instance_variable_get(:@clinic)
        }
      )
    end

    # ... helpers de renderização
  end
end
```

> O template ERB `pdf_layout.html.erb` injeta header com logo da clínica, footer com paginação e CSS embarcado pra impressão (A4, margens, fontes).

### `DocumentTemplates::PdfGenerator` — HTML → PDF

```ruby
module DocumentTemplates
  class PdfGenerator
    def initialize(template:, patient:, professional:, clinic: nil, save_to: nil)
      @template = template
      @patient = patient
      @professional = professional
      @clinic = clinic || patient.account
      @save_to = save_to  # Document or ConsentRecord instance
    end

    def call!
      html = render_html
      pdf_bytes = html_to_pdf(html)
      hash = Digest::SHA256.hexdigest(pdf_bytes)

      if @save_to
        attach_to_record(@save_to, pdf_bytes, html, hash)
      end

      { html: html, pdf_bytes: pdf_bytes, hash: hash }
    end

    private

    def render_html
      resolver = Resolver.new(patient: @patient, clinic: @clinic, professional: @professional)
      Renderer.new(template: @template, resolver: resolver).render
    end

    def html_to_pdf(html)
      Grover.new(
        html,
        format: @template.paper_size || 'A4',
        landscape: @template.orientation == 'landscape',
        margin: { top: '20mm', right: '15mm', bottom: '20mm', left: '15mm' },
        print_background: true,
        display_url: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
        prefer_css_page_size: true
      ).to_pdf
    end

    def attach_to_record(record, pdf_bytes, html, hash)
      record.transaction do
        record.update!(
          document_template_id: @template.id,
          rendered_html: html,
          pdf_hash: hash
        )
        record.file.attach(
          io: StringIO.new(pdf_bytes),
          filename: "#{record.title.parameterize}-v#{record.try(:version) || 1}.pdf",
          content_type: 'application/pdf'
        )
      end
    end
  end
end
```

### `DocumentTemplates::CloneKlivyTemplate`

```ruby
module DocumentTemplates
  class CloneKlivyTemplate
    def initialize(klivy_template:, account:, user:, folder: nil)
      @klivy_template = klivy_template
      @account = account
      @user = user
      @folder = folder
    end

    def call!
      DocumentTemplate.create!(
        account: @account,
        folder: @folder,
        created_by_user: @user,
        source: 'cloned',
        source_template: @klivy_template,
        name: @klivy_template.name,
        description: @klivy_template.description,
        document_type: @klivy_template.document_type,
        content_json: @klivy_template.content_json.deep_dup,
        paper_size: @klivy_template.paper_size,
        orientation: @klivy_template.orientation,
        status: 'active',
        version: 1
      )
    end
  end
end
```

## 4.6 Job: geração assíncrona de PDF

```ruby
# app/jobs/document_templates/generate_pdf_job.rb
module DocumentTemplates
  class GeneratePdfJob < ApplicationJob
    queue_as :default

    def perform(record_class:, record_id:, template_id:, professional_id:)
      record = record_class.constantize.find(record_id)
      template = DocumentTemplate.find(template_id)
      professional = User.find(professional_id)

      PdfGenerator.new(
        template: template,
        patient: record.patient,
        professional: professional,
        save_to: record
      ).call!

      record.update!(status: 'gerado') if record.respond_to?(:status=)
      broadcast_completion(record)
    end

    private

    def broadcast_completion(record)
      # Re-uso do padrão Action Cable que já existe em telemed/agenda
      ActionCable.server.broadcast(
        "account_#{record.account_id}",
        type: 'document_pdf_ready',
        document_id: record.id,
        url: record.file.url
      )
    end
  end
end
```

## 4.7 Policies (autorização)

```ruby
class DocumentTemplatePolicy < ApplicationPolicy
  def index?;     true;                       end
  def show?;      record.account_id == user.account_id || record.klivy?; end
  def create?;    user.administrator?;        end
  def update?;    user.administrator? && record.account_id == user.account_id; end
  def destroy?;   user.administrator? && record.account_id == user.account_id; end
  def duplicate?; user.administrator?;        end
end
```

Klivy templates são read-only pra clínica (clone obrigatório pra editar).

## 4.8 Engine — integração com modelos existentes

```ruby
# plugins/document_templates/lib/document_templates/engine.rb
require 'rails/engine'

module DocumentTemplates
  class Engine < ::Rails::Engine
    isolate_namespace DocumentTemplates

    config.to_prepare do
      Rails.application.config.paths['app/services'] << "#{DocumentTemplates::Engine.root}/app/services"
      Document.include(DocumentTemplateExtension)
      ConsentRecord.include(DocumentTemplateExtension)
    end
  end
end
```

## 4.9 Integração com `Patients::PdfGenerator`

Mexer no `pdf_generator.rb` existente pra escolher renderer:

```ruby
# plugins/patients/app/services/patients/pdf_generator.rb (modificado)
module Patients
  class PdfGenerator
    def initialize(patient:, document_type:, professional:, template_id: nil, variables: {})
      @template_id = template_id
      # ... existente
    end

    def call!
      if @template_id.present?
        delegate_to_new_engine
      else
        legacy_prawn_generation
      end
    end

    private

    def delegate_to_new_engine
      template = DocumentTemplate.for_account(@patient.account).find(@template_id)
      document = build_document_record(template: template)

      DocumentTemplates::PdfGenerator.new(
        template: template,
        patient: @patient,
        professional: @professional,
        save_to: document
      ).call!

      document
    end

    def legacy_prawn_generation
      # código atual intocado
    end
  end
end
```

## 4.10 Validações importantes do `content_json`

Pra evitar lixo no JSON (XSS, payloads gigantes):

```ruby
# DocumentTemplate#validate_content_json_structure (expandido)

def validate_content_json_structure
  errors.add(:content_json, 'must be a hash') unless content_json.is_a?(Hash)
  errors.add(:content_json, 'must be a ProseMirror doc') unless content_json['type'] == 'doc'

  size_bytes = content_json.to_json.bytesize
  if size_bytes > 500_000  # 500 KB
    errors.add(:content_json, "exceeds 500KB (#{size_bytes} bytes)")
  end

  validate_no_dangerous_nodes(content_json)
end

DANGEROUS_NODE_TYPES = %w[script iframe object embed].freeze

def validate_no_dangerous_nodes(node)
  return if node.nil?
  if DANGEROUS_NODE_TYPES.include?(node['type'])
    errors.add(:content_json, "contains forbidden node type: #{node['type']}")
  end
  Array(node['content']).each { |child| validate_no_dangerous_nodes(child) }
end
```

## 4.11 Performance & monitoramento

- **Logging estruturado** (já existe padrão no projeto via Sentry e audit_logged).
- Métricas: tempo de geração de PDF, taxa de erro do Chromium, fila Sidekiq.
- Time-out do Grover: 30s default — abortar se exceder.
- Cache do `content_html_cached` opcionalmente (sem dados de paciente, só pra preview do admin).
