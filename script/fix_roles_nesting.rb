require 'fileutils'
dir = "/home/danilo/KlivyApp/plugins/beclinic_core/frontend/settings/BeClinicRoles"

nested_dir = File.join(dir, 'BeClinicRoles')

if Dir.exist?(nested_dir)
  Dir.glob(File.join(nested_dir, '*')).each do |file|
    FileUtils.mv(file, dir)
  end
  FileUtils.rm_rf(nested_dir)
  puts "Fixed BeClinicRoles nesting issue!"
else
  puts "No nesting issue found."
end
