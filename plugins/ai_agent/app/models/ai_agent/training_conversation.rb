# Uma conversa de WhatsApp exportada (.zip) que a clínica sobe na aba
# "Treinamento" da Bea. O pipeline (AiAgent::ProcessTrainingConversationJob)
# destila o histórico em FAQs. 1 registro = 1 .zip enviado.
#
# O conteúdo bruto (texto + áudio) é EFÊMERO: processado no job e descartado
# ao final (LGPD / ~5GB de mídia). Aqui ficam só metadados, progresso e o
# resultado parseado — este já com a PII mascarada e purgado quando o ciclo
# completo (Fase 4) estiver pronto.
class AiAgent::TrainingConversation < ApplicationRecord
  self.table_name = 'ai_agent_training_conversations'

  belongs_to :account

  has_one_attached :zip_file

  enum :status, {
    pending: 0,        # na fila, ainda não processado
    extracting: 1,     # estágios 0-1: descompacta + parser
    transcribing: 2,   # estágio 2: transcreve os áudios
    extracting_faq: 3, # estágios 3-5: blocagem + extração + consolidação
    completed: 4,
    failed: 5,
    awaiting_clinic: 6 # detectou os participantes; espera o usuário escolher a clínica
  }

  MAX_ZIP_SIZE = 200.megabytes
  ZIP_CONTENT_TYPES = ['application/zip', 'application/x-zip-compressed', 'multipart/x-zip'].freeze

  validates :name, presence: true, length: { maximum: 255 }
  # Opcional na criação: quando ausente, o job detecta os participantes e
  # aguarda o usuário escolher a clínica (status awaiting_clinic).
  validates :clinic_sender_name, length: { maximum: 255 }
  # Só na criação: depois de processar, o .zip é purgado (estágio 6 / LGPD),
  # então exigir o anexo em updates posteriores quebraria status e publicação.
  validate :validate_zip_attachment, on: :create

  scope :ordered, -> { order(created_at: :desc) }

  private

  def validate_zip_attachment
    return errors.add(:zip_file, 'must be attached') unless zip_file.attached?

    errors.add(:zip_file, 'must be a .zip file') unless ZIP_CONTENT_TYPES.include?(zip_file.content_type)
    errors.add(:zip_file, "must be smaller than #{MAX_ZIP_SIZE / 1.megabyte} MB") if zip_file.byte_size > MAX_ZIP_SIZE
  end
end
