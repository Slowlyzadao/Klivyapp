require 'fileutils'

base_dir = File.expand_path('../plugins/financial', __dir__)
directories = [
  'app/models/financial',
  'app/controllers/financial/api/v1',
  'config',
  'lib/financial',
  'frontend'
]

directories.each do |dir|
  FileUtils.mkdir_p(File.join(base_dir, dir))
end

engine_content = <<-RUBY
module Financial
  class Engine < ::Rails::Engine
    isolate_namespace Financial

    config.to_prepare do
      # Adicionaremos associacoes injetadas depois
    end
  end
end
RUBY

File.write(File.join(base_dir, 'lib', 'financial', 'engine.rb'), engine_content)

module_content = <<-RUBY
module Financial
  def self.table_name_prefix
    'financial_'
  end
end
RUBY

File.write(File.join(base_dir, 'lib', 'financial.rb'), module_content)

puts 'Financial engine stub generated successfully!'
