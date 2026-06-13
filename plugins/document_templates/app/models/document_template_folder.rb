# Pasta organizadora de DocumentTemplates dentro de uma clínica.
#
# Schema suporta hierarquia (parent_id) mas o MVP da UI só usa pastas raiz.
# Subpastas ficam pra Fase 2 se houver demanda — o `:restrict_with_error` em
# `has_many :children` protege contra deletar pasta com subpastas até lá.
#
# Templates Klivy globais (account_id NULL) NÃO ficam em pastas — eles
# aparecem numa seção dedicada "Biblioteca Klivy" no UI.
class DocumentTemplateFolder < ApplicationRecord
  belongs_to :account
  belongs_to :parent, class_name: 'DocumentTemplateFolder', optional: true

  has_many :children,
           class_name: 'DocumentTemplateFolder',
           foreign_key: 'parent_id',
           dependent: :restrict_with_error

  has_many :templates,
           class_name: 'DocumentTemplate',
           foreign_key: 'folder_id',
           dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 120 }
  validates :name,
            uniqueness: { scope: [:account_id, :parent_id], case_sensitive: false }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate  :parent_must_belong_to_same_account

  scope :roots, -> { where(parent_id: nil).order(:position, :name) }

  private

  def parent_must_belong_to_same_account
    return if parent.blank?
    return if parent.account_id == account_id

    errors.add(:parent, 'must belong to the same account')
  end
end
