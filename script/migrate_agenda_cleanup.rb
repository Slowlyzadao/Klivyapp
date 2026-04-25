require 'fileutils'

PROJECT_ROOT = File.expand_path('..', __dir__)

files_to_delete = [
  'app/models/agenda_event.rb',
  'app/models/agenda_custom_attribute.rb',
  'app/models/agenda_notification_log.rb',
  'app/models/agenda_notification_rule.rb',
  'app/models/agenda_online_config.rb',
  'app/models/agenda_service.rb',
  'app/models/agenda_setting.rb',
  'app/models/waiting_list_entry.rb',
  'app/controllers/api/v1/accounts/agenda_events_controller.rb',
  'app/controllers/api/v1/accounts/agenda_custom_attributes_controller.rb',
  'app/controllers/api/v1/accounts/agenda_notification_logs_controller.rb',
  'app/controllers/api/v1/accounts/agenda_notification_rules_controller.rb',
  'app/controllers/api/v1/accounts/agenda_online_config_controller.rb',
  'app/controllers/api/v1/accounts/agenda_reports_controller.rb',
  'app/controllers/api/v1/accounts/agenda_services_controller.rb',
  'app/controllers/api/v1/accounts/agenda_settings_controller.rb',
  'app/controllers/api/v1/accounts/waiting_list_entries_controller.rb',
  'app/services/agenda/notification_template_service.rb',
  'app/jobs/agenda/notification_dispatcher_job.rb',
  'app/jobs/agenda/send_notification_job.rb'
]

puts "🚀 Starting Backend Cleanup for Agenda Engine..."

files_to_delete.each do |f|
  path = File.join(PROJECT_ROOT, f)
  if File.exist?(path)
    File.delete(path)
    puts "✅ Deleted #{f}"
  else
    puts "⚠️ File already gone: #{f}"
  end
end

puts "🎉 Cleanup complete! Ensure `plugins/agenda/app/...` holds the logic."
