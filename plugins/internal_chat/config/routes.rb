# Rotas do plugin internal_chat são registradas no config/routes.rb da host app
# (mesmo padrão de agenda/ai_agent), pois engines não conseguem se enganchar
# no scope :accounts do Chatwoot depois que o roteador é finalizado.
