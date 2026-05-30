# 03 — Modelo de Dados

## 3.1 Tabelas novas

### `document_template_folders`

Organização hierárquica dos templates. No MVP, uso só raiz (sem subpastas), mas o schema suporta.

```ruby
create_table :document_template_folders do |t|
  t.references :account, null: false, foreign_key: true, index: true
  t.references :parent,  foreign_key: { to_table: :document_template_folders }, index: true
  t.string  :name,           null: false, limit: 120
  t.integer :position,       null: false, default: 0
  t.string  :color,          limit: 16        # opcional: cor da pasta no UI
  t.string  :icon,           limit: 32        # opcional: ícone (lucide)
  t.timestamps
end

add_index :document_template_folders, [:account_id, :parent_id, :position]
add_index :document_template_folders, [:account_id, :name], unique: true,
          where: 'parent_id IS NULL'   # nome único por raiz
```

**Notas:**
- `account_id` é mandatório (pasta sempre pertence a uma clínica — pastas Klivy não existem; templates Klivy são listados em seção separada no UI).
- `parent_id` nullable pra subpastas futuras.
- `position` pra drag-and-drop manual.
- Soft delete não é necessário (deletar pasta com templates → bloquear ou mover pra raiz).

### `document_templates`

Tabela central da feature.

```ruby
create_table :document_templates do |t|
  t.references :account,
               null: true,    # NULL apenas pra templates Klivy globais
               foreign_key: true,
               index: true
  t.references :folder,
               foreign_key: { to_table: :document_template_folders },
               index: true
  t.references :created_by_user,
               foreign_key: { to_table: :users },
               index: true
  t.references :source_template,
               foreign_key: { to_table: :document_templates },
               index: true

  t.string  :name,         null: false, limit: 200
  t.text    :description                       # opcional, ajuda na descoberta
  t.integer :document_type, null: false
  # 0-10 = clínico (igual Document)
  # 100-111 = consentimento (igual ConsentRecord type)

  t.jsonb   :content_json, null: false, default: {}
  # Estrutura: documento ProseMirror. Validado por schema TipTap.
  # Ex.: { type: 'doc', content: [ { type: 'paragraph', ... } ] }

  t.text    :content_html_cached
  # Cache opcional do HTML pra acelerar preview no admin.
  # Não usar pro PDF final (sempre rerenderiza com dados do paciente).

  t.string  :source,       null: false, default: 'clinic'
  # enum: 'klivy' (template global da Klivy), 'clinic' (criado pela clínica),
  #       'cloned' (clínica clonou um Klivy)

  t.string  :status,       null: false, default: 'active'
  # enum: 'draft', 'active', 'archived'

  t.integer :version,      null: false, default: 1
  # Incrementa a cada save substancial. Mostra no UI ("v3").

  t.string  :paper_size,   default: 'A4'      # A4, Letter, A5
  t.string  :orientation,  default: 'portrait' # portrait, landscape
  t.jsonb   :metadata,     default: {}
  # Espaço pra extensões futuras: tags, custom_data, ai_generated_flag, etc.

  t.datetime :archived_at
  t.timestamps
end

add_index :document_templates, [:account_id, :document_type, :status]
add_index :document_templates, [:account_id, :folder_id]
add_index :document_templates, [:source, :document_type],
          where: "account_id IS NULL"  # acelera busca dos modelos Klivy globais
add_index :document_templates, :archived_at
```

**Constraints lógicas (validações Ruby):**
- `account_id IS NULL` ⟺ `source = 'klivy'` (templates Klivy são globais).
- `source = 'cloned'` ⟹ `source_template_id IS NOT NULL`.
- `folder_id`, quando preenchido, deve ter o mesmo `account_id`.
- `name` único por `(account_id, folder_id)` — sem dois templates com o mesmo nome na mesma pasta.

### `document_template_usages` (opcional — pode ficar pra Fase 2)

Tracking de quem usou qual template e quando — útil pra analytics e ordenação por "mais usados".

```ruby
create_table :document_template_usages do |t|
  t.references :document_template, null: false, foreign_key: true
  t.references :user,               null: false, foreign_key: true
  t.references :account,            null: false, foreign_key: true
  t.string     :context,            limit: 32  # 'document' | 'consent_record'
  t.bigint     :target_id                       # id do Document ou ConsentRecord
  t.timestamps
end

add_index :document_template_usages, [:document_template_id, :created_at]
add_index :document_template_usages, [:account_id, :created_at]
```

> **Decisão MVP**: pular essa tabela e popular `document_templates.metadata->'usage_count'` em background. Mais simples, performance suficiente.

## 3.2 Modificações em tabelas existentes

### `documents` (plugin patients) — adicionar colunas

```ruby
change_table :documents do |t|
  t.references :document_template, foreign_key: true, index: true
  # NULL = gerado pelo caminho legado (Prawn).
  # Quando preenchido: documento veio do editor novo.

  t.text       :rendered_html
  # HTML congelado do documento gerado (com variáveis já resolvidas).
  # Imutável — fonte da verdade pra reimprimir/auditoria.

  t.string     :pdf_hash, limit: 64
  # SHA-256 hex do PDF anexado. Prova de integridade.
  # Preparação pra Clicksign (Fase 2).
end

add_index :documents, :pdf_hash
```

### `consent_records` (plugin patients) — adicionar colunas

```ruby
change_table :consent_records do |t|
  t.references :document_template, foreign_key: true, index: true
  t.text       :rendered_html
  # Body do consentimento renderizado pelo editor novo.
  # Quando preenchido, é mostrado em vez do campo `body` legado.

  t.string     :pdf_hash, limit: 64
end

add_index :consent_records, :pdf_hash
```

## 3.3 Modelos ActiveRecord

### `DocumentTemplate`

```ruby
class DocumentTemplate < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :folder, class_name: 'DocumentTemplateFolder', optional: true
  belongs_to :created_by_user, class_name: 'User', optional: true
  belongs_to :source_template, class_name: 'DocumentTemplate', optional: true

  has_many :clones, class_name: 'DocumentTemplate',
                    foreign_key: 'source_template_id',
                    dependent: :nullify
  has_many :documents, dependent: :restrict_with_error
  has_many :consent_records, dependent: :restrict_with_error

  enum document_type: {
    # Documentos clínicos (espelha Document.document_type)
    receita: 0, atestado: 1, pedido_exame: 2, declaracao: 3,
    relatorio_clinico: 4, encaminhamento: 5, contrato: 6, orcamento: 7,
    instrucao_procedimento: 8, questionario: 9, outro: 10,
    # Consentimentos
    consentimento_geral: 100, consentimento_lgpd: 101, consentimento_imagem: 102,
    consentimento_toxina: 103, consentimento_preenchimento: 104,
    consentimento_laser: 105, consentimento_fototerapia_led: 106,
    consentimento_peeling: 107, consentimento_dermoabrasao: 108,
    consentimento_menor: 109, consentimento_cirurgico: 110,
    consentimento_anestesia: 111
  }

  enum source: { clinic: 'clinic', klivy: 'klivy', cloned: 'cloned' }
  enum status: { draft: 'draft', active: 'active', archived: 'archived' }

  validates :name, presence: true, length: { maximum: 200 }
  validates :document_type, presence: true
  validates :content_json, presence: true
  validate  :validate_account_consistency
  validate  :validate_content_json_structure

  scope :for_account, ->(account) {
    where(account_id: [account.id, nil])  # próprios + Klivy globais
  }
  scope :clinical,   -> { where(document_type: 0..10) }
  scope :consents,   -> { where('document_type >= 100') }

  before_save :bump_version, if: :content_json_changed?
  before_save :clear_html_cache, if: :content_json_changed?

  def family
    document_type_before_type_cast >= 100 ? :consent : :clinical
  end

  private

  def validate_account_consistency
    if source == 'klivy' && account_id.present?
      errors.add(:account_id, 'must be null for Klivy templates')
    elsif source != 'klivy' && account_id.blank?
      errors.add(:account_id, 'must be present for non-Klivy templates')
    end
  end

  def validate_content_json_structure
    return if content_json.is_a?(Hash) && content_json['type'] == 'doc'
    errors.add(:content_json, 'must be a valid ProseMirror document')
  end

  def bump_version
    self.version = (version || 0) + 1
  end

  def clear_html_cache
    self.content_html_cached = nil
  end
end
```

### `DocumentTemplateFolder`

```ruby
class DocumentTemplateFolder < ApplicationRecord
  belongs_to :account
  belongs_to :parent, class_name: 'DocumentTemplateFolder', optional: true

  has_many :children, class_name: 'DocumentTemplateFolder',
                       foreign_key: 'parent_id',
                       dependent: :restrict_with_error
  has_many :templates, class_name: 'DocumentTemplate',
                        foreign_key: 'folder_id',
                        dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 120 }
  validates :name, uniqueness: { scope: [:account_id, :parent_id] }

  scope :roots, -> { where(parent_id: nil).order(:position) }
end
```

### Extensão de `Document` (via concern em plugins/patients)

```ruby
# plugins/document_templates/app/models/concerns/document_template_extension.rb
module DocumentTemplateExtension
  extend ActiveSupport::Concern

  included do
    belongs_to :document_template, optional: true

    scope :from_template, -> { where.not(document_template_id: nil) }
    scope :legacy,        -> { where(document_template_id: nil) }
  end

  def generated_from_template?
    document_template_id.present?
  end

  def renderer
    generated_from_template? ? :grover : :prawn
  end
end

# plugins/document_templates/lib/document_templates/engine.rb
config.to_prepare do
  Document.include(DocumentTemplateExtension)
  ConsentRecord.include(DocumentTemplateExtension)
end
```

## 3.4 Migrations — ordem de execução

1. `CreateDocumentTemplateFolders`
2. `CreateDocumentTemplates`
3. `AddTemplateRefToDocuments`
4. `AddTemplateRefToConsentRecords`
5. `(opcional) CreateDocumentTemplateUsages`

Todas devem rodar **sem downtime**: adicionam colunas/tabelas, não alteram comportamento — o caminho legado continua intacto enquanto `document_template_id` é null.

## 3.5 Estimativa de volume

| Tabela | Linhas estimadas/clínica/ano | Tamanho médio/linha | Total ano (1000 clínicas) |
|---|---|---|---|
| `document_templates` | 30 | ~5 KB (JSON médio) | 150 MB |
| `document_template_folders` | 8 | ~200 B | 1.6 MB |
| `documents.rendered_html` (novo) | 2000 (estimado) | ~10 KB | 20 GB |
| `consent_records.rendered_html` | 500 | ~8 KB | 4 GB |

**Atenção:** `rendered_html` cresce significativamente com o uso. Considerar:
- Compressão Postgres TOAST (automático pra TEXT > 2KB).
- Política de retenção em `documents` antigos (já existe `archived_at`).
- Em escala alta, migrar `rendered_html` pra Active Storage (blob separado).

## 3.6 Soft delete

Hoje `Document` tem `archived_at` (soft delete). Manter mesmo padrão em `document_templates` (`archived_at` + scope `active`).
**Não usar paranoia/discard gem nova** — segue o padrão atual do projeto.

## 3.7 Backfill / seeds

### Seed do catálogo Klivy

Roda em `db/seeds.rb` (ou seed específico):

```ruby
DocumentTemplates::SeedKlivyLibrary.call!
```

Cria ~15-20 templates `source: 'klivy'`, `account_id: nil`, distribuídos entre tipos clínicos e consentimentos.

**Idempotente**: usa `find_or_create_by(name:, source: 'klivy', document_type:)`.

### Migração dos atuais

Detalhado em [08-migracao-prawn.md](08-migracao-prawn.md). Resumindo: cada um dos 10 tipos do `Document` e 11 do `ConsentRecord` ganha um template Klivy equivalente (em JSON ProseMirror) — o conteúdo é extraído do código atual do Prawn e convertido.
