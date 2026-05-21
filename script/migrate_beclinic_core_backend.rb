require 'fileutils'
require 'pathname'

root = Pathname.new(__dir__).join('..')
plugin_root = root.join('plugins/beclinic_core/app')

puts "🚀 Migrating Beclinic Core Backend Files to Plugin..."

# 1. Models/Concerns
concerns_src = root.join('app/models/concerns/beclinic_permissible.rb')
concerns_dest = plugin_root.join('models/concerns/beclinic_permissible.rb')

if concerns_src.exist?
  FileUtils.mv(concerns_src, concerns_dest)
  puts "✅ Moved beclinic_permissible (Concern) to plugin"
end

# 2. Controllers
controllers_src = root.join('app/controllers/api/v1/accounts/beclinic_permissions_controller.rb')
controllers_dest = plugin_root.join('controllers/api/v1/accounts/beclinic_permissions_controller.rb')

if controllers_src.exist?
  FileUtils.mv(controllers_src, controllers_dest)
  puts "✅ Moved beclinic_permissions_controller to plugin"
end

puts "🎉 Backend Core Core scripts completed!"
