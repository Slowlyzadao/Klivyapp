require 'fileutils'

base_dir = File.join(__dir__, '..', 'plugins', 'patients')
directories = [
  'app/models',
  'app/controllers/api/v1/accounts/patients',
  'app/services',
  'app/jobs',
  'config/initializers',
  'lib/patients',
  'frontend/api',
  'frontend/store',
  'frontend/routes',
  'frontend/features',
  'frontend/components'
].map { |dir| File.join(base_dir, dir) }

FileUtils.mkdir_p(directories)

# Engine file
engine_content = <<~RUBY
  module Patients
    class Engine < ::Rails::Engine
      isolate_namespace Patients

      config.to_prepare do
        # Injeção de dependências no Core
        Account.class_eval do
          has_many :patients, dependent: :destroy
        end

        Contact.class_eval do
          has_one :patient, dependent: :nullify
        end

        User.class_eval do
          has_many :responsible_patients, class_name: 'Patient', foreign_key: 'responsible_professional_id', dependent: :nullify
        end
      end
    end
  end
RUBY

File.write(File.join(base_dir, 'lib', 'patients', 'engine.rb'), engine_content)

# Module main file
module_content = <<~RUBY
  require 'patients/engine'

  module Patients
  end
RUBY

File.write(File.join(base_dir, 'lib', 'patients.rb'), module_content)

puts 'Patients engine stub generated successfully!'
