require 'fileutils'

base_dir = File.expand_path('../plugins/beclinic_core', __dir__)
directories = [
  'app/models',
  'app/models/concerns',
  'app/controllers/api/v1/accounts',
  'config',
  'lib/beclinic_core',
  'frontend',
  'frontend/api',
  'frontend/store/modules/beclinicPermissions',
  'frontend/settings/BeClinicRoles'
]

directories.each do |dir|
  FileUtils.mkdir_p(File.join(base_dir, dir))
end

engine_content = <<-RUBY
module BeclinicCore
  class Engine < ::Rails::Engine
    isolate_namespace BeclinicCore

    config.to_prepare do
      # Adicionaremos associacoes e inclusao dinamica no core de User/Team
      User.class_eval do
        # include BeclinicPermissible sera portado dinamicamente
      end
    end
  end
end
RUBY

File.write(File.join(base_dir, 'lib', 'beclinic_core', 'engine.rb'), engine_content)

puts 'Beclinic Core engine stub generated successfully!'
