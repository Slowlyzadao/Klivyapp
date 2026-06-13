# Larger context block (~1500 chars). Used for answer generation, never
# embedded — children carry the embeddings and point back to their parent.
class AiAgent::ParentChunk < ApplicationRecord
  self.table_name = 'ai_agent_parent_chunks'

  belongs_to :document, class_name: 'AiAgent::Document'
  has_many :child_chunks,
           class_name: 'AiAgent::ChildChunk',
           dependent: :destroy

  validates :content, presence: true
  validates :position, presence: true, uniqueness: { scope: :document_id }

  before_save :recompute_char_count

  private

  def recompute_char_count
    self.char_count = content.to_s.length
  end
end
