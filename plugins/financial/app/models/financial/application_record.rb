module Financial
  class ApplicationRecord < ::ApplicationRecord
    self.abstract_class = true

    include Financial::Concerns::SoftDeletable
    include Financial::Concerns::Auditable
    include Financial::Concerns::Stamped
    include Financial::Concerns::MoneyAttribute

    scope :for_account, ->(account_id) { where(account_id: account_id) }
  end
end
