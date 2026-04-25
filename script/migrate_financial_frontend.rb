require 'fileutils'
require 'pathname'

root = Pathname.new(__dir__).join('..')
plugin_frontend = root.join('plugins/financial/frontend')

# 1. Routes e Componentes Vue do Feature
old_routes_dir = root.join('app/javascript/dashboard/features/financial')
new_routes_dir = plugin_frontend.join('features/financial')

if old_routes_dir.exist?
  FileUtils.mkdir_p(new_routes_dir.parent)
  FileUtils.mv(old_routes_dir, new_routes_dir)
  puts "✅ Moved frontend features and routes to plugin"
else
  puts "⚠️ Source features/financial directory not found!"
end

puts "🎉 Frontend separation script completed!"
