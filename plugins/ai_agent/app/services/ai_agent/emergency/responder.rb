# Templates fixos por categoria. Texto NÃO passa pelo LLM —
# qualquer parafraseamento criativo aqui pode confundir o
# paciente em momento de risco (e abrir flanco de compliance,
# CFM 2.454/2026). Mantemos curtos, com número de telefone
# destacado, e escala humana sempre.
class AiAgent::Emergency::Responder
  MESSAGES = {
    clinical: <<~MSG.strip,
      Pelo que você descreveu, isso pode ser uma emergência. Ligue agora para o SAMU 192 ou vá ao pronto-socorro mais próximo. Já estou avisando a equipe da clínica também — alguém vai entrar em contato com você.
    MSG
    suicidal: <<~MSG.strip
      Eu te ouço, e quero que saiba que você não está sozinha(o). O CVV (Centro de Valorização da Vida) atende 24 horas por dia, gratuito, no telefone 188 ou pelo chat em cvv.org.br. Estou avisando agora a nossa equipe para entrar em contato com você também.
    MSG
  }.freeze

  def self.message_for(category)
    MESSAGES[category.to_sym] || MESSAGES[:clinical]
  end
end
