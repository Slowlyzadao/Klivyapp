require 'fileutils'
dir = "\\\\wsl.localhost\\Ubuntu\\home\\danilo\\KlivyApp\\plugins\\beclinic_core\\frontend\\store\\modules\\beclinicPermissions"

nested_dir = File.join(dir, 'beclinicPermissions')

if Dir.exist?(nested_dir)
  Dir.glob(File.join(nested_dir, '*')).each do |file|
    FileUtils.mv(file, dir)
  end
  FileUtils.rm_rf(nested_dir)
  puts "Fixed nesting issue!"
else
  puts "No nesting issue found."
end
