require 'fileutils'
require 'pathname'

root = Pathname.new(__dir__).join('..')
plugin_frontend = root.join('plugins/patients/frontend')

# 1. Routes and Components
old_routes_dir = root.join('app/javascript/dashboard/routes/dashboard/patients')
new_routes_dir = plugin_frontend.join('routes')

if old_routes_dir.exist?
  FileUtils.mkdir_p(new_routes_dir.parent)
  FileUtils.mv(old_routes_dir, new_routes_dir)
  puts "✅ Moved frontend routes and components to plugin"
end

# 2. APIs
old_api_dir = root.join('app/javascript/dashboard/api/patients')
new_api_dir = plugin_frontend.join('api/patients')

if old_api_dir.exist?
  FileUtils.mkdir_p(new_api_dir.parent)
  FileUtils.mv(old_api_dir, new_api_dir)
  puts "✅ Moved frontend APIs to plugin"
end

puts "🎉 Frontend separation script completed!"
