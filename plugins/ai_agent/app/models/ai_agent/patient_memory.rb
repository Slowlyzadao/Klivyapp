module AiAgent
  # Long-term memory keyed by Chatwoot contact_id. Holds preferences and a
  # capped history of significant events ("agendou consulta no dia X",
  # "alergia a anestesia local declarada", etc.). The agent reads this at the
  # top of each conversation and writes back at the end.
  class PatientMemory < ApplicationRecord
    self.table_name = 'ai_agent_patient_memories'

    HISTORY_LIMIT = 50

    belongs_to :account

    validates :contact_id, presence: true,
                           uniqueness: { scope: :account_id }

    def self.for(account:, contact_id:)
      find_or_create_by!(account_id: account.id, contact_id: contact_id)
    end

    def set_preference(key, value)
      preferences[key.to_s] = value
      save!
    end

    def append_history(event_type:, summary:, metadata: {})
      entry = {
        'type' => event_type,
        'summary' => summary,
        'metadata' => metadata,
        'at' => Time.current.iso8601
      }
      self.history = (history + [entry]).last(HISTORY_LIMIT)
      save!
    end
  end
end
