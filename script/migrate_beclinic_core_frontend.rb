require 'fileutils'
require 'pathname'

root = Pathname.new(__dir__).join('..')
plugin_frontend = root.join('plugins/beclinic_core/frontend')

# 1. Rotas e View do Settings
old_routes_dir = root.join('app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles')
if old_routes_dir.exist?
  FileUtils.mv(old_routes_dir, plugin_frontend.join('settings/BeClinicRoles'))
  puts "✅ Moved settings/BeClinicRoles views to plugin"
end

# 2. Store Vuex
old_store_dir = root.join('app/javascript/dashboard/store/modules/beclinicPermissions')
if old_store_dir.exist?
  FileUtils.mkdir_p(plugin_frontend.join('store/modules'))
  FileUtils.mv(old_store_dir, plugin_frontend.join('store/modules/beclinicPermissions'))
  puts "✅ Moved store/beclinicPermissions to plugin"
end

# 3. API Clients
api_files = ['beclinicPermissions.js', 'beclinicRoles.js']
api_files.each do |f|
  src = root.join('app/javascript/dashboard/api', f)
  if src.exist?
    FileUtils.mv(src, plugin_frontend.join('api', f))
    puts "✅ Moved api/#{f} to plugin"
  end
end

puts "🎉 Frontend Core separation script completed!"
