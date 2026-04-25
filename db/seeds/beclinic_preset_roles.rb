# db/seeds/beclinic_preset_roles.rb
#
# Cria os 4 Times/Perfis padrão do RBAC para uma conta específica.
# Este seeder é chamado ao criar uma nova conta no sistema.
#
# Uso:
#   Beclinic::PresetRolesSeeder.seed_for!(account)
#
module Beclinic
  class PresetRolesSeeder
    PRESETS = [
      {
        key: 'recepcionista',
        name: 'recepcionista',
        description: 'Gerencia agendamentos, cadastros e atendimento inicial dos pacientes.',
        allow_auto_assign: true
      },
      {
        key: 'especialista',
        name: 'especialista',
        description: 'Acesso ao prontuário dos próprios pacientes, evoluções e planos de tratamento.',
        allow_auto_assign: true
      },
      {
        key: 'gerente',
        name: 'gerente',
        description: 'Acesso completo à clínica, financeiro, relatórios e gestão de usuários.',
        allow_auto_assign: false
      },
      {
        key: 'sdr',
        name: 'sdr / comercial',
        description: 'Focado em agendamentos, atendimento via chat e gestão de orçamentos.',
        allow_auto_assign: true
      }
    ].freeze

    def self.seed_for!(account)
      new(account).seed!
    end

    def initialize(account)
      @account = account
    end

    def seed!
      PRESETS.each do |preset|
        next if @account.teams.exists?(name: preset[:name])

        perms = Team::PRESET_PERMISSIONS[preset[:key]].deep_dup
        next unless perms

        role = perms.delete(:beclinic_role) { 'especialista' }
        permissions_data = perms.transform_values { |v| v.transform_keys(&:to_s) }
                               .transform_keys(&:to_s)

        @account.teams.create!(
          name: preset[:name],
          description: preset[:description],
          allow_auto_assign: preset[:allow_auto_assign],
          beclinic_role: role,
          is_preset: true,
          permissions: permissions_data
        )
      end
    end
  end
end
