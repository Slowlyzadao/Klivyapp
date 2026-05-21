class ExamFolder < ApplicationRecord
  belongs_to :patient
  belongs_to :account
  belongs_to :parent, class_name: 'ExamFolder', optional: true
  has_many :children, class_name: 'ExamFolder', foreign_key: :parent_id, dependent: :destroy
  has_many :exam_medias, dependent: :nullify

  MAX_NAME_LENGTH = 80

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :patient_id, presence: true
  validates :account_id, presence: true
  validate :max_one_level_nesting
  validate :parent_in_same_patient
  validate :no_self_parent

  before_validation :assign_account_from_patient

  scope :ordered, -> { order(:position, :id) }
  scope :roots,   -> { where(parent_id: nil) }

  private

  def assign_account_from_patient
    self.account_id ||= patient&.account_id
  end

  def max_one_level_nesting
    return unless parent&.parent_id.present?

    errors.add(:parent_id, 'subpastas não podem conter subpastas (máx. 1 nível de aninhamento)')
  end

  def parent_in_same_patient
    return if parent_id.blank?
    return if parent && parent.patient_id == patient_id

    errors.add(:parent_id, 'pasta-pai deve pertencer ao mesmo paciente')
  end

  def no_self_parent
    return if parent_id.blank? || id.blank?
    return unless parent_id == id

    errors.add(:parent_id, 'pasta não pode ser pai de si mesma')
  end
end
