require 'fileutils'
require 'pathname'

root = Pathname.new(__dir__).join('..')
plugin_root = root.join('plugins/patients/app')

models_to_move = %w[
  patient.rb
  patient_appointment.rb
  patient_audit_log.rb
  patient_timeline_event.rb
  anamnesis.rb
  clinical_note.rb
  consent_record.rb
  critical_alert.rb
  document.rb
  exam_folder.rb
  exam_media.rb
  treatment_plan.rb
  treatment_item.rb
  session_log.rb
]

puts "🚀 Migrating Patients Backend Files to Plugin..."

models_to_move.each do |model|
  src = root.join('app/models', model)
  dest = plugin_root.join('models', model)
  if src.exist?
    FileUtils.mv(src, dest)
    puts "✅ Moved #{model} to plugin"
  else
    puts "⚠️ #{model} not found in core"
  end
end

# Controllers
controllers_dir = root.join('app/controllers/api/v1/accounts/patients')
dest_controllers_dir = plugin_root.join('controllers/api/v1/accounts/patients')

if controllers_dir.exist?
  FileUtils.mkdir_p(dest_controllers_dir.parent)
  FileUtils.mv(controllers_dir, dest_controllers_dir.parent)
  puts "✅ Moved patients controllers directory"
end

base_controller = root.join('app/controllers/api/v1/accounts/patients_controller.rb')
if base_controller.exist?
  FileUtils.mv(base_controller, plugin_root.join('controllers/api/v1/accounts/'))
  puts "✅ Moved patients_controller.rb"
end

puts "🎉 Backend separation scripts completed!"
