require 'fileutils'

PROJECT_ROOT = File.expand_path('..', __dir__)

def safe_move(src, dest_dir)
  src_path = File.join(PROJECT_ROOT, src)
  dest_path = File.join(PROJECT_ROOT, dest_dir)

  unless File.exist?(src_path)
    puts "⚠️ Source not found: #{src}"
    return
  end

  FileUtils.mkdir_p(dest_path)
  
  if File.directory?(src_path)
    FileUtils.mv(src_path, dest_path)
    puts "✅ Moved #{src} to #{dest_path}"
  else
    FileUtils.mv(src_path, dest_path)
    puts "✅ Moved #{src} to #{dest_path}"
  end
rescue => e
  puts "❌ Error moving #{src}: #{e.message}"
end

puts "🚀 Migrating Agenda Frontend Files to Plugin..."

# 1. Routes and Components
safe_move('app/javascript/dashboard/routes/agenda', 'plugins/agenda/frontend/')
begin
  agenda_dir = File.join(PROJECT_ROOT, 'plugins/agenda/frontend/agenda')
  routes_dir = File.join(PROJECT_ROOT, 'plugins/agenda/frontend/routes')
  if File.directory?(agenda_dir)
    FileUtils.mv(agenda_dir, routes_dir)
    puts "✅ Renamed frontend/agenda to frontend/routes"
  end
rescue => e
  puts "❌ Error renaming to routes: #{e.message}"
end

# 2. Store Modules
['agendaEvents.js', 'agendaNotificationRules.js', 'agendaServices.js'].each do |file|
  src = "app/javascript/dashboard/store/modules/#{file}"
  safe_move(src, 'plugins/agenda/frontend/store') if File.exist?(File.join(PROJECT_ROOT, src))
end

# 3. API Modules
[
  'agendaCustomAttributes.js',
  'agendaEvents.js',
  'agendaNotificationLogs.js',
  'agendaNotificationRules.js',
  'agendaReports.js',
  'agendaServices.js',
  'agendaSettings.js'
].each do |file|
  src = "app/javascript/dashboard/api/#{file}"
  safe_move(src, 'plugins/agenda/frontend/api') if File.exist?(File.join(PROJECT_ROOT, src))
end

# 4. Features (summary widget, etc. if they exist)
['agenda-summary', 'waiting-list'].each do |feature|
  src = "app/javascript/dashboard/features/#{feature}"
  if File.exist?(File.join(PROJECT_ROOT, src))
    safe_move(src, 'plugins/agenda/frontend/features')
  end
end

puts "🎉 Migration script finished!"
