user = User.first
account = Account.first
note = ClinicalNote.last
puts "User ID: #{user.id}, email: #{user.email}, auth role: #{user.role}"
puts "Signed?: #{note.status_signed?}"
policy = ClinicalNotePolicy.new({user: user, account: account}, note)
puts "Can update?: #{policy.update?}"
puts "Admin/Supervisor?: #{policy.send(:administrator_or_supervisor?)}"
puts "Administrator?: #{user.administrator?}"
puts "Custom Role name: #{user.custom_role&.name}"
