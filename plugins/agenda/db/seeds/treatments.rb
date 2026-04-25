# Seed padrão de tratamentos para a Agenda
# Executar com: docker exec beclinic-rails-1 bundle exec rails runner plugins/agenda/db/seeds/treatments.rb

account = Account.find(1)

treatments = [
  { name: 'Avaliação',           duration_minutes: 30,  color: '#3b82f6', price: 0 },
  { name: 'Profilaxia',          duration_minutes: 60,  color: '#22c55e', price: 0 },
  { name: 'Periodontia',         duration_minutes: 60,  color: '#eab308', price: 0 },
  { name: 'Endodontia',          duration_minutes: 90,  color: '#ef4444', price: 0 },
  { name: 'Reavaliação',         duration_minutes: 30,  color: '#f97316', price: 0 },
  { name: 'Implante Individual', duration_minutes: 120, color: '#8b5cf6', price: 0 },
  { name: 'Protocolo Sup/Inf',   duration_minutes: 180, color: '#6366f1', price: 0 },
]

treatments.each do |t|
  service = account.agenda_services.find_or_initialize_by(name: t[:name])
  if service.new_record?
    service.assign_attributes(t)
    service.save!
    puts "✅ Criado: #{t[:name]}"
  else
    puts "⏭️  Já existe: #{t[:name]}"
  end
end

puts "\n📋 Total de tratamentos: #{account.agenda_services.count}"
