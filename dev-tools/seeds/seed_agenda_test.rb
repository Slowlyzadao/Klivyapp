account = Account.first

puts "Criando serviços..."
services = [
  AgendaService.create!(account: account, name: "Terapia Cognitiva", duration_minutes: 50, price: 150.0, color: "#10b981"),
  AgendaService.create!(account: account, name: "Retorno", duration_minutes: 30, price: 0.0, color: "#f59e0b"),
  AgendaService.create!(account: account, name: "Clínico Geral", duration_minutes: 60, price: 200.0, color: "#8b5cf6")
]

puts "Criando 5 novos agentes..."
agents = []
5.times do |i|
  email = "agente_teste_#{i+1}@acme.inc"
  user = User.find_or_create_by!(email: email) do |u|
    u.name = "Dr. Teste #{i+1}"
    u.password = "P@ssword123"
    u.password_confirmation = "P@ssword123"
  end
  # Cria o vínculo com a conta, caso não exista
  AccountUser.find_or_create_by!(account: account, user: user) do |au|
    au.role = 0 # role: agent (enum) - base de agente
  end
  agents << user
end

# Para garantir variedade, também vamos incluir o agent atual Gustavo e John (se existirem na base)
all_agents = account.users.to_a

puts "Criando pacientes (contacts)..."
contacts = []
10.times do |i|
  contacts << Contact.create!(account: account, name: "Paciente Teste #{i+1}", email: "paciente#{i+1}@teste.com", phone_number: "+551199999000#{i}")
end

start_date = Time.zone.local(2026, 4, 5)
end_date = Time.zone.local(2026, 4, 11)

puts "Criando eventos entre #{start_date.to_date} e #{end_date.to_date}..."

statuses = ['scheduled', 'confirmed', 'completed', 'arrived']

# Criar cerca de 40 eventos para popular bem a semana
40.times do |i|
  # Escolhe um dia aleatório na semana
  day_offset = rand(0..6)
  current_day = start_date + day_offset.days
  
  # Escolhe um horário entre 8h e 17h
  hour = rand(8..17)
  # Minutos em intervalos de 30 (0 ou 30)
  minute = [0, 30].sample
  
  starts_at = current_day.change(hour: hour, min: minute)
  
  service = services.sample
  ends_at = starts_at + service.duration_minutes.minutes
  
  event_status = statuses.sample
  # Se o horário já passou, faz sentido estar completed ou na frente scheduled
  
  agent = all_agents.sample
  contact = contacts.sample
  
  # Custom attributes
  custom_attrs = {
    treatment: service.name,
    priority: ['low', 'medium', 'high'].sample,
    notes: "Evento gerado automaticamente para teste."
  }
  
  AgendaEvent.create!(
    account: account,
    user: agent,
    contact: contact,
    title: "#{service.name} - #{contact.name}",
    starts_at: starts_at,
    ends_at: ends_at,
    status: event_status,
    custom_attributes: custom_attrs
  )
end

puts "=== DADOS GERADOS COM SUCESSO ==="
puts "Novos agentes criados: #{agents.map(&:name).join(', ')}"
puts "Eventos criados: 40"
puts "Serviços adicionados: #{services.map(&:name).join(', ')}"
