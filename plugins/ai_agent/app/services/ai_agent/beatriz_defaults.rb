module AiAgent
  # Single source of truth for Beatriz's default Captain::Assistant config.
  # Used both at account creation (engine.rb) and when reading/merging in the
  # PromptBuilder, so a fresh assistant ships with usable handoff/resolution
  # messages and an empty clinic profile schema the user can fill in.
  module BeatrizDefaults
    HANDOFF_MESSAGE = 'Vou te transferir agora pra um atendente humano. Só um instante. 🙏'.freeze
    RESOLUTION_MESSAGE = 'Conseguimos te ajudar? Se precisar de mais alguma coisa, é só me chamar por aqui. 💜'.freeze

    # Manual fields only — name and address. Business hours and services are
    # pulled live from the Agenda plugin (AgendaSetting / AgendaService) so
    # the user doesn't have to maintain the same data twice.
    CLINIC_PROFILE_SCHEMA = {
      'name'    => '',
      'address' => ''
    }.freeze

    def self.config
      {
        'bea_enabled'        => true,
        'handoff_message'    => HANDOFF_MESSAGE,
        'resolution_message' => RESOLUTION_MESSAGE,
        'clinic_profile'     => CLINIC_PROFILE_SCHEMA.dup
      }
    end
  end
end
