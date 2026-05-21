# == Schema Information
#
# Table name: agenda_services
#
#  id               :bigint           not null, primary key
#  account_id       :bigint           not null
#  uuid             :uuid             default: gen_random_uuid()
#  external_id      :string           limit: 100
#  name             :string           not null
#  duration_minutes :integer          not null, default: 60
#  price            :decimal          precision: 10, scale: 2, default: 0
#  requires_room    :boolean          not null, default: false
#  color            :string           default: '#3b82f6'
#  position         :integer          default: 0
#  deleted_at       :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_agenda_services_on_account_id                  (account_id)
#  index_agenda_services_on_account_id_and_position     (account_id, position)
#  index_agenda_services_on_account_id_and_deleted_at   (account_id, deleted_at)
#  uniq_agenda_services_account_lower_btrim_name        (account_id, lower(btrim(name))) UNIQUE WHERE deleted_at IS NULL
#  uniq_agenda_services_uuid                            (uuid) UNIQUE
#  uniq_agenda_services_account_external_id             (account_id, external_id) UNIQUE WHERE external_id IS NOT NULL
#

class AgendaService < ApplicationRecord
  # PR #8 da auditoria 2026-05-13: auditoria automática via concern.
  # Registra create/update/archive/restore em `agenda_audit_logs` async.
  # Soft-delete (PR #1) é detectado pelo concern e logado como `archive`
  # — diferenciado de update normal pra facilitar relatórios de compliance.
  include Agenda::Concerns::Auditable

  belongs_to :account

  # PR #4 da auditoria 2026-05-13: FK reversa explícita.
  # `dependent: :nullify` cobre o caso raro de HARD-delete via `destroy!`
  # direto (bypass do soft-delete). O FK do banco com `ON DELETE SET NULL`
  # já garante consistência mesmo se alguém deletar via SQL — esta linha é
  # defense in depth no nível Rails.
  # Soft-delete (`deleted_at`) preserva a linha → eventos continuam apontando
  # para o serviço arquivado, possibilitando UI mostrar "Serviço arquivado".
  has_many :agenda_events, dependent: :nullify

  # 9.7 da auditoria 2026-05-14: vínculo serviço↔profissional.
  # Sem vínculos = "qualquer profissional pode oferecer" (compat pré-9.7).
  # Com 1+ vínculos = só os profissionais vinculados aparecem no link
  # público do profissional respectivo.
  has_many :agenda_service_users, dependent: :destroy
  has_many :professionals, through: :agenda_service_users, source: :user

  # Helper usado pelo `Public::Api::V1::Agenda::PublicController` para
  # decidir se um serviço deve aparecer/ser aceito num link público de
  # determinado profissional. Mantém o fallback de compat: serviço sem
  # vínculos = liberado pra todos.
  def offered_by?(user_id)
    return true if agenda_service_users.empty?
    agenda_service_users.where(user_id: user_id).exists?
  end

  # ─── Soft-delete ─────────────────────────────────────────────────────────────
  # Padrão alinhado com AgendaEvent (mesmo plugin) e Patient.active: `deleted_at`
  # nulo = ativo, preenchido = arquivado. Não usamos a gem `discard` porque o
  # resto do plugin usa convenção manual.
  scope :kept,      -> { where(deleted_at: nil) }
  scope :discarded, -> { where.not(deleted_at: nil) }

  # `ordered` agora exclui soft-deletados — a UI só vê serviços ativos.
  # Eventos antigos que referenciam um serviço soft-deletado via
  # `custom_attributes['treatment']` continuam funcionando (string preserva o
  # NAME); só somem da listagem da aba "Serviços" e do select de novo evento.
  scope :ordered, -> { kept.order(:position, :created_at) }

  # ─── Validações ──────────────────────────────────────────────────────────────
  # `case_sensitive: false` + `conditions: kept` casam com o unique index parcial
  # em `lower(btrim(name)) WHERE deleted_at IS NULL`. Sem o `conditions:`, a
  # validação Ruby barra a recriação de um nome que existe soft-deletado —
  # divergindo do índice (que libera) e quebrando a UX esperada de
  # "excluir e criar de novo com o mesmo nome".
  # Backup defensivo em Ruby: se duas requisições simultâneas baterem antes do
  # constraint, o Rails ainda rejeita uma com mensagem amigável (em vez de
  # PG::UniqueViolation cru).
  validates :name, presence: { message: 'é obrigatório' },
                   uniqueness: {
                     scope: :account_id,
                     case_sensitive: false,
                     conditions: -> { kept },
                     message: 'já está em uso por outro serviço cadastrado'
                   }
  validates :duration_minutes, presence: { message: 'é obrigatória' },
                               numericality: {
                                 greater_than: 0,
                                 message: 'deve ser maior que zero'
                               }
  validates :price, numericality: {
    greater_than_or_equal_to: 0,
    message: 'não pode ser negativo'
  }, allow_nil: true

  # PR #2 da auditoria 2026-05-13: external_id idempotente para importadores.
  # Unique por account quando preenchido — espelha o índice parcial do banco.
  # `allow_nil: true` permite serviços manuais sem external_id (maioria dos casos).
  validates :external_id, uniqueness: {
    scope: :account_id,
    allow_nil: true,
    message: 'já está em uso por outro serviço importado'
  }

  before_validation :normalize_name
  before_create :set_position

  # Traduz os nomes de atributo no `full_messages` do ActiveRecord — sem isso
  # a mensagem fica "Name já está em uso..." misturando PT/EN. O controller usa
  # `errors.full_messages.to_sentence`, então essa tradução chega no JSON 422.
  def self.human_attribute_name(attr, options = {})
    {
      name: 'Nome',
      duration_minutes: 'Duração',
      price: 'Preço',
      color: 'Cor',
      requires_room: 'Exige sala'
    }[attr.to_sym] || super
  end

  # ─── Soft-delete API ─────────────────────────────────────────────────────────
  # Em vez de `destroy!` físico (que deixaria eventos antigos órfãos sem aviso),
  # marcamos `deleted_at`. O controller chama isto no `destroy` action.
  # Reversível por `update!(deleted_at: nil)` manual se necessário.
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def discarded?
    deleted_at.present?
  end

  private

  # Strip de whitespace lateral. Bloqueia duplicatas como "Limpeza" vs
  # " Limpeza " que diferiam só por espaço lateral antes do unique index.
  def normalize_name
    self.name = name.to_s.strip if name.present?
  end

  # PR #3 da auditoria 2026-05-13: serializa criações simultâneas na mesma
  # conta via PostgreSQL advisory lock transacional.
  #
  # Bug original (B1, C9): `max + 1` sem lock — duas requisições simultâneas
  # podiam ler o mesmo `max_pos` e gerar registros com `position` duplicada.
  # Não corrompia dados graves, mas bagunçava a ordenação (`order(:position)`
  # ficava ambígua entre duplicados).
  #
  # `pg_advisory_xact_lock` libera automaticamente no commit/rollback da
  # transação do save (Rails envolve o INSERT em transação). Chave dupla
  # `(hashtext(nome), account_id)` evita colisão com outros usos de advisory
  # lock no mesmo banco. `account_id.to_i` blinda contra SQL injection.
  def set_position
    if account_id.present?
      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_xact_lock(hashtext('agenda_service_position'), #{account_id.to_i})"
      )
    end
    max_pos = account.agenda_services.kept.maximum(:position) || -1
    self.position = max_pos + 1
  end
end
