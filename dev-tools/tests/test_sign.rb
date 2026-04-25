actor = User.first
Current.account = Account.first
Current.user = actor
note = ClinicalNote.create!(patient_id: 22, account_id: 1, professional_id: 1, note_date: Date.today, status: "draft")

puts "Initial Status: #{note.status}"

res = Patients::ClinicalNoteSignerService.call(note: note, actor: actor)
puts "Result success: #{res.success?}"
puts "Result error: #{res.error}"
