require 'fileutils'
require 'pathname'

root = Pathname.new(__dir__).join('..')
plugin_root = root.join('plugins/patients/app')

controllers_dir = root.join('app/controllers/api/v1/accounts/patients')
dest_controllers_dir = plugin_root.join('controllers/api/v1/accounts/patients')

if controllers_dir.exist?
  # The directory already exists empty on destination because setup script created it.
  # Let's move its contents instead or remove the destination and move the dir itself.
  FileUtils.rm_rf(dest_controllers_dir) if dest_controllers_dir.exist? && dest_controllers_dir.empty?
  FileUtils.mv(controllers_dir, dest_controllers_dir.parent)
  puts "✅ Moved patients controllers directory successfully"
else
  puts "⚠️ Source controllers directory not found (maybe already moved?)"
end

base_controller = root.join('app/controllers/api/v1/accounts/patients_controller.rb')
if base_controller.exist?
  FileUtils.mv(base_controller, plugin_root.join('controllers/api/v1/accounts/'))
  puts "✅ Moved patients_controller.rb"
end

puts "🎉 Backend separation fix completed!"
