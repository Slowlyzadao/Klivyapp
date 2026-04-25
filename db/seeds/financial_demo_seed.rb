# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# Financial Demo Seed – Clínica Odontológica Realista
# ═══════════════════════════════════════════════════════════════════════════════
# Uso:  bundle exec rails runner db/seeds/financial_demo_seed.rb
# ═══════════════════════════════════════════════════════════════════════════════

account = Account.first
abort '❌ Nenhuma Account encontrada. Crie ao menos uma antes.' unless account

admin_account_user = AccountUser.find_by(account: account, role: :administrator) || AccountUser.find_by(account: account)
abort '❌ Nenhum User encontrado na account.' unless admin_account_user

admin = admin_account_user.user

puts '🏥 Iniciando seed da demo financeira para clínica odontológica...'
puts "   Account: #{account.id} – #{account.name}"
puts "   Admin: #{admin.id} – #{admin.name}"

# ── Helpers ──────────────────────────────────────────────────────────────────
def rand_between(a, b)
  rand(a..b)
end

def random_cpf
  Array.new(11) { rand(0..9) }.join
end

today = Date.today
this_month_start = today.beginning_of_month
last_month_start = (today - 1.month).beginning_of_month

# ═══════════════════════════════════════════════════════════════════════════════
# 1. CONTAS BANCÁRIAS
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n💳 Criando contas bancárias..."

bank_accounts_data = [
  { name: 'Conta Corrente Itaú', bank_name: 'Itaú', bank_code: '341', account_type: 'checking', initial_balance: 15_000.0 },
  { name: 'Conta Corrente Bradesco', bank_name: 'Bradesco', bank_code: '237', account_type: 'checking', initial_balance: 8_500.0 },
  { name: 'Poupança Nubank', bank_name: 'Nubank', bank_code: '260', account_type: 'savings', initial_balance: 25_000.0 },
  { name: 'Caixa da Clínica', bank_name: nil, bank_code: nil, account_type: 'cash', initial_balance: 2_000.0 }
]

bank_accounts = bank_accounts_data.map do |data|
  BankAccount.find_or_create_by!(account: account, name: data[:name]) do |ba|
    ba.assign_attributes(data)
  end
end
puts "   ✅ #{bank_accounts.size} contas bancárias"

# ═══════════════════════════════════════════════════════════════════════════════
# 2. CATEGORIAS FINANCEIRAS
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n📂 Criando categorias financeiras..."

income_categories_data = [
  { name: 'Consultas', color: '#22c55e', icon: 'i-lucide-stethoscope', cost_type: nil },
  { name: 'Procedimentos Estéticos', color: '#3b82f6', icon: 'i-lucide-sparkles', cost_type: nil },
  { name: 'Ortodontia', color: '#8b5cf6', icon: 'i-lucide-align-center', cost_type: nil },
  { name: 'Implantes', color: '#06b6d4', icon: 'i-lucide-circle-dot', cost_type: nil },
  { name: 'Endodontia', color: '#f59e0b', icon: 'i-lucide-crosshair', cost_type: nil },
  { name: 'Periodontia', color: '#ec4899', icon: 'i-lucide-heart-pulse', cost_type: nil },
  { name: 'Próteses', color: '#14b8a6', icon: 'i-lucide-box', cost_type: nil },
  { name: 'Radiologia', color: '#64748b', icon: 'i-lucide-scan', cost_type: nil }
]

expense_categories_data = [
  { name: 'Despesas Operacionais', color: '#ef4444', icon: 'i-lucide-building-2', cost_type: 'fixo' },
  { name: 'Aluguel', color: '#f97316', icon: 'i-lucide-home', cost_type: 'fixo' },
  { name: 'Materiais Odontológicos', color: '#a855f7', icon: 'i-lucide-package', cost_type: 'variavel' },
  { name: 'Salários e Encargos', color: '#6366f1', icon: 'i-lucide-users', cost_type: 'fixo' },
  { name: 'Marketing e Publicidade', color: '#06b6d4', icon: 'i-lucide-megaphone', cost_type: 'variavel' },
  { name: 'Manutenção de Equipamentos', color: '#78716c', icon: 'i-lucide-wrench', cost_type: 'variavel' },
  { name: 'Energia e Água', color: '#eab308', icon: 'i-lucide-zap', cost_type: 'fixo' },
  { name: 'Laboratório de Prótese', color: '#f43f5e', icon: 'i-lucide-flask-conical', cost_type: 'variavel' },
  { name: 'Software e Tecnologia', color: '#0ea5e9', icon: 'i-lucide-monitor', cost_type: 'fixo' },
  { name: 'Impostos e Tributos', color: '#dc2626', icon: 'i-lucide-receipt', cost_type: 'fixo' }
]

income_cats = income_categories_data.each_with_index.map do |data, idx|
  FinancialCategory.find_or_create_by!(account: account, name: data[:name], category_type: 'income') do |fc|
    fc.assign_attributes(data.merge(position: idx, is_default: idx < 3))
  end
end

expense_cats = expense_categories_data.each_with_index.map do |data, idx|
  FinancialCategory.find_or_create_by!(account: account, name: data[:name], category_type: 'expense') do |fc|
    fc.assign_attributes(data.merge(position: idx, is_default: idx < 3))
  end
end

puts "   ✅ #{income_cats.size} categorias de receita, #{expense_cats.size} categorias de despesa"

# ═══════════════════════════════════════════════════════════════════════════════
# 3. PACIENTES
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n👥 Criando pacientes..."

patients_data = [
  { name: 'Ana Clara Oliveira', phone: '11987654321', email: 'ana.clara@email.com', sex: 'feminino', birthdate: Date.new(1988, 3, 15), patient_status: 'ativo',
    insurance: { name: 'Bradesco Dental', plan: 'Premium', number: 'BD-12345' } },
  { name: 'Carlos Eduardo Silva', phone: '11976543210', email: 'carlos.edu@email.com', sex: 'masculino', birthdate: Date.new(1975, 7, 22), patient_status: 'ativo',
    insurance: { name: 'Porto Seguro Odonto', plan: 'Empresarial', number: 'PS-67890' } },
  { name: 'Maria Fernanda Costa', phone: '11965432109', email: 'maria.f@email.com', sex: 'feminino', birthdate: Date.new(1992, 11, 8), patient_status: 'ativo',
    insurance: { name: 'Unimed Dental', plan: 'Standard', number: 'UN-11111' } },
  { name: 'João Pedro Santos', phone: '11954321098', email: 'joao.pedro@email.com', sex: 'masculino', birthdate: Date.new(1983, 1, 30), patient_status: 'ativo',
    insurance: {} },
  { name: 'Beatriz Almeida', phone: '11943210987', email: 'bia.almeida@email.com', sex: 'feminino', birthdate: Date.new(1995, 5, 12), patient_status: 'ativo',
    insurance: { name: 'Bradesco Dental', plan: 'Básico', number: 'BD-22222' } },
  { name: 'Roberto Ferreira Lima', phone: '11932109876', email: 'roberto.lima@email.com', sex: 'masculino', birthdate: Date.new(1968, 9, 3), patient_status: 'ativo',
    insurance: { name: 'Amil Dental', plan: 'Premium', number: 'AM-33333' } },
  { name: 'Juliana Martins Souza', phone: '11921098765', email: 'juliana.ms@email.com', sex: 'feminino', birthdate: Date.new(1990, 12, 25), patient_status: 'ativo',
    insurance: { name: 'Porto Seguro Odonto', plan: 'Individual', number: 'PS-44444' } },
  { name: 'Fernando Henrique Rocha', phone: '11910987654', email: 'fernando.hr@email.com', sex: 'masculino', birthdate: Date.new(1979, 4, 18), patient_status: 'inativo',
    insurance: {} },
  { name: 'Camila Rodrigues Pinto', phone: '11909876543', email: 'camila.rp@email.com', sex: 'feminino', birthdate: Date.new(2001, 6, 7), patient_status: 'novo',
    insurance: { name: 'Unimed Dental', plan: 'Familiar', number: 'UN-55555' } },
  { name: 'Lucas Barbosa Neto', phone: '11898765432', email: 'lucas.bn@email.com', sex: 'masculino', birthdate: Date.new(1985, 10, 14), patient_status: 'faltoso',
    no_show_count: 4, insurance: {} },
  { name: 'Patricia Mendes Dias', phone: '11887654321', email: 'patricia.md@email.com', sex: 'feminino', birthdate: Date.new(1993, 2, 28), patient_status: 'ativo',
    insurance: { name: 'Bradesco Dental', plan: 'Premium', number: 'BD-66666' } },
  { name: 'André Luiz Campos', phone: '11876543210', email: 'andre.lc@email.com', sex: 'masculino', birthdate: Date.new(1971, 8, 19), patient_status: 'ativo',
    insurance: { name: 'Amil Dental', plan: 'Empresarial', number: 'AM-77777' } },
  { name: 'Isabela Cristina Xavier', phone: '11865432109', email: 'isabela.cx@email.com', sex: 'feminino', birthdate: Date.new(1998, 4, 5), patient_status: 'novo',
    insurance: {} },
  { name: 'Ricardo Moreira Gomes', phone: '11854321098', email: 'ricardo.mg@email.com', sex: 'masculino', birthdate: Date.new(1960, 11, 22), patient_status: 'ativo',
    insurance: { name: 'Porto Seguro Odonto', plan: 'Premium', number: 'PS-88888' } },
  { name: 'Larissa Duarte Vieira', phone: '11843210987', email: 'larissa.dv@email.com', sex: 'feminino', birthdate: Date.new(1987, 7, 11), patient_status: 'alta',
    insurance: { name: 'Unimed Dental', plan: 'Premium', number: 'UN-99999' } }
]

patients = patients_data.map do |data|
  Patient.find_or_create_by!(account: account, name: data[:name]) do |p|
    p.assign_attributes(
      data.merge(
        cpf: random_cpf,
        responsible_professional: admin,
        address: {
          street: "Rua #{['das Flores', 'São Paulo', 'XV de Novembro', 'Bela Vista', 'Augusta', 'Paulista', 'Consolação'].sample}",
          number: rand(100..3000).to_s,
          neighborhood: ['Centro', 'Jardins', 'Pinheiros', 'Vila Mariana', 'Moema', 'Itaim Bibi', 'Brooklin'].sample,
          city: 'São Paulo',
          state: 'SP',
          zip_code: "0#{rand(1000..5999)}0-#{rand(100..999)}"
        }
      )
    )
  end
end

puts "   ✅ #{patients.size} pacientes criados"

# ═══════════════════════════════════════════════════════════════════════════════
# 4. AGENDAMENTOS (PASSADOS E FUTUROS)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n📅 Criando agendamentos..."

appointment_count = 0
appointment_types = PatientAppointment::APPOINTMENT_TYPES

# Agendamentos passados (concluídos, no_show)
patients.first(12).each do |patient|
  rand_between(2, 5).times do |i|
    scheduled = (today - rand_between(5, 60).days).change(hour: rand_between(8, 17), min: [0, 30].sample)
    status = i == 0 && patient.patient_status == 'faltoso' ? 'no_show' : 'done'

    PatientAppointment.find_or_create_by!(
      account: account,
      patient: patient,
      scheduled_at: scheduled
    ) do |appt|
      appt.professional = admin
      appt.appointment_type = appointment_types.sample
      appt.status = status
      appt.duration_minutes = [30, 45, 60].sample
      appt.notes = ['Paciente pontual', 'Atendimento realizado sem intercorrências', 'Necessário retorno', nil].sample
    end
    appointment_count += 1
  end
end

# Agendamentos futuros (scheduled, confirmed)
patients.first(8).each do |patient|
  rand_between(1, 3).times do
    scheduled = (today + rand_between(1, 30).days).change(hour: rand_between(8, 17), min: [0, 30].sample)

    PatientAppointment.find_or_create_by!(
      account: account,
      patient: patient,
      scheduled_at: scheduled
    ) do |appt|
      appt.professional = admin
      appt.appointment_type = appointment_types.sample
      appt.status = %w[scheduled confirmed].sample
      appt.duration_minutes = [30, 45, 60].sample
    end
    appointment_count += 1
  end
end

puts "   ✅ #{appointment_count} agendamentos"

# ═══════════════════════════════════════════════════════════════════════════════
# 5. TRANSAÇÕES FINANCEIRAS
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n💰 Criando transações financeiras..."

txn_count = 0
payment_methods = AccountTransaction::PAYMENT_METHODS
insurance_names = ['Bradesco Dental', 'Porto Seguro Odonto', 'Unimed Dental', 'Amil Dental', 'Particular']

# ── 5A. ENTRADAS RECEBIDAS (mês atual e passado) ─────────────────────────────
entries_data = [
  # Mês atual - receitas variadas
  { desc: 'Consulta avaliação – Ana Clara',      patient_idx: 0,  cat: 'Consultas',              amount: 350,    insurance: 'Bradesco Dental', days_ago: 2 },
  { desc: 'Limpeza + Profilaxia – Carlos',       patient_idx: 1,  cat: 'Consultas',              amount: 280,    insurance: 'Porto Seguro Odonto', days_ago: 3 },
  { desc: 'Clareamento dental – Maria',          patient_idx: 2,  cat: 'Procedimentos Estéticos', amount: 1_800,  insurance: 'Unimed Dental', days_ago: 4 },
  { desc: 'Manutenção ortodôntica – João',       patient_idx: 3,  cat: 'Ortodontia',             amount: 450,    insurance: 'Particular', days_ago: 5 },
  { desc: 'Consulta retorno – Beatriz',          patient_idx: 4,  cat: 'Consultas',              amount: 250,    insurance: 'Bradesco Dental', days_ago: 6 },
  { desc: 'Implante unitário – Roberto',         patient_idx: 5,  cat: 'Implantes',              amount: 4_500,  insurance: 'Amil Dental', days_ago: 7 },
  { desc: 'Tratamento canal – Juliana',          patient_idx: 6,  cat: 'Endodontia',             amount: 1_200,  insurance: 'Porto Seguro Odonto', days_ago: 8 },
  { desc: 'Raspagem periodontal – Patricia',     patient_idx: 10, cat: 'Periodontia',            amount: 600,    insurance: 'Bradesco Dental', days_ago: 9 },
  { desc: 'Prótese parcial – André',             patient_idx: 11, cat: 'Próteses',               amount: 2_800,  insurance: 'Amil Dental', days_ago: 10 },
  { desc: 'Radiografia panorâmica – Camila',     patient_idx: 8,  cat: 'Radiologia',             amount: 180,    insurance: 'Unimed Dental', days_ago: 11 },
  { desc: 'Faceta de porcelana – Ana Clara',     patient_idx: 0,  cat: 'Procedimentos Estéticos', amount: 2_200,  insurance: 'Bradesco Dental', days_ago: 12 },
  { desc: 'Consulta avaliação – Ricardo',        patient_idx: 13, cat: 'Consultas',              amount: 350,    insurance: 'Porto Seguro Odonto', days_ago: 13 },
  { desc: 'Manutenção aparelho – Beatriz',       patient_idx: 4,  cat: 'Ortodontia',             amount: 380,    insurance: 'Bradesco Dental', days_ago: 14 },
  { desc: 'Extração siso – Carlos',              patient_idx: 1,  cat: 'Consultas',              amount: 550,    insurance: 'Porto Seguro Odonto', days_ago: 1 },
  { desc: 'Lente de contato dental – Juliana',   patient_idx: 6,  cat: 'Procedimentos Estéticos', amount: 3_500,  insurance: 'Particular', days_ago: 3 },
  # Mês passado
  { desc: 'Implante carga imediata – Roberto',   patient_idx: 5,  cat: 'Implantes',              amount: 6_800,  insurance: 'Amil Dental', days_ago: 35 },
  { desc: 'Consulta – Maria',                    patient_idx: 2,  cat: 'Consultas',              amount: 290,    insurance: 'Unimed Dental', days_ago: 38 },
  { desc: 'Canal molar – André',                 patient_idx: 11, cat: 'Endodontia',             amount: 1_500,  insurance: 'Amil Dental', days_ago: 40 },
  { desc: 'Prótese total – Ricardo',             patient_idx: 13, cat: 'Próteses',               amount: 4_200,  insurance: 'Porto Seguro Odonto', days_ago: 42 },
  { desc: 'Ortodontia instalação – Beatriz',     patient_idx: 4,  cat: 'Ortodontia',             amount: 3_000,  insurance: 'Bradesco Dental', days_ago: 45 }
]

entries_data.each do |data|
  received_date = today - data[:days_ago].days
  cat = income_cats.find { |c| c.name == data[:cat] }
  patient = patients[data[:patient_idx]]

  AccountTransaction.find_or_create_by!(
    account: account,
    description: data[:desc],
    entry_type: 'entrada'
  ) do |txn|
    txn.patient = patient
    txn.financial_category = cat
    txn.bank_account = bank_accounts.sample
    txn.registered_by = admin
    txn.professional = admin
    txn.amount = data[:amount]
    txn.status = 'recebido'
    txn.payment_method = payment_methods.sample
    txn.received_at = received_date
    txn.competence_date = received_date
    txn.due_date = received_date
    txn.origin = 'manual'
    txn.metadata = { 'insurance' => data[:insurance] }
  end
  txn_count += 1
end

# ── 5B. ENTRADAS PENDENTES (a receber) ──────────────────────────────────────
receivables_data = [
  { desc: 'Implante 2ª etapa – Roberto (parcela 2/3)', patient_idx: 5,  cat: 'Implantes',              amount: 3_200, due_days: -5, insurance: 'Amil Dental' },
  { desc: 'Ortodontia mensalidade – João (Jan)',        patient_idx: 3,  cat: 'Ortodontia',             amount: 450,   due_days: -15, insurance: 'Particular' },
  { desc: 'Prótese ajuste final – André',               patient_idx: 11, cat: 'Próteses',               amount: 1_400, due_days: 5, insurance: 'Amil Dental' },
  { desc: 'Clareamento 2ª sessão – Maria',             patient_idx: 2,  cat: 'Procedimentos Estéticos', amount: 900,   due_days: 10, insurance: 'Unimed Dental' },
  { desc: 'Consulta retorno – Camila',                 patient_idx: 8,  cat: 'Consultas',              amount: 280,   due_days: 0, insurance: 'Unimed Dental' },
  { desc: 'Implante osseointegração – Roberto',        patient_idx: 5,  cat: 'Implantes',              amount: 3_200, due_days: 15, insurance: 'Amil Dental' },
  { desc: 'Faceta cerâmica – Patricia',                patient_idx: 10, cat: 'Procedimentos Estéticos', amount: 2_500, due_days: 20, insurance: 'Bradesco Dental' },
  { desc: 'Manutenção ortodôntica – Beatriz (Mar)',    patient_idx: 4,  cat: 'Ortodontia',             amount: 380,   due_days: 25, insurance: 'Bradesco Dental' }
]

receivables_data.each do |data|
  due = today + data[:due_days].days
  cat = income_cats.find { |c| c.name == data[:cat] }
  patient = patients[data[:patient_idx]]

  AccountTransaction.find_or_create_by!(
    account: account,
    description: data[:desc],
    entry_type: 'entrada'
  ) do |txn|
    txn.patient = patient
    txn.financial_category = cat
    txn.bank_account = bank_accounts.first
    txn.registered_by = admin
    txn.professional = admin
    txn.amount = data[:amount]
    txn.status = 'pendente'
    txn.payment_method = payment_methods.sample
    txn.due_date = due
    txn.competence_date = due.beginning_of_month
    txn.origin = 'manual'
    txn.metadata = { 'insurance' => data[:insurance] }
  end
  txn_count += 1
end

# ── 5C. SAÍDAS PAGAS (despesas efetivadas) ──────────────────────────────────
expenses_paid_data = [
  { desc: 'Aluguel do consultório – Março',       cat: 'Aluguel',                       amount: 5_800, days_ago: 1 },
  { desc: 'Folha de pagamento – Março',           cat: 'Salários e Encargos',            amount: 12_500, days_ago: 5 },
  { desc: 'Resina composta 3M (30 seringas)',     cat: 'Materiais Odontológicos',        amount: 1_890, days_ago: 8 },
  { desc: 'Anestésico Articaína (100 tubetes)',   cat: 'Materiais Odontológicos',        amount: 420,   days_ago: 10 },
  { desc: 'Conta de luz – Fev/Mar',              cat: 'Energia e Água',                 amount: 890,   days_ago: 12 },
  { desc: 'Google Ads – campanha Março',          cat: 'Marketing e Publicidade',        amount: 1_500, days_ago: 15 },
  { desc: 'Laboratório prótese – pedido #245',   cat: 'Laboratório de Prótese',         amount: 3_200, days_ago: 7 },
  { desc: 'Manutenção cadeira odontológica',      cat: 'Manutenção de Equipamentos',     amount: 780,   days_ago: 20 },
  { desc: 'Licença software gestão (mensal)',     cat: 'Software e Tecnologia',          amount: 299,   days_ago: 2 },
  { desc: 'ISS + Simples Nacional – Fevereiro',  cat: 'Impostos e Tributos',            amount: 2_450, days_ago: 18 },
  { desc: 'Luvas, máscaras e EPIs',              cat: 'Materiais Odontológicos',        amount: 650,   days_ago: 6 },
  { desc: 'Instagram Ads – Stories',             cat: 'Marketing e Publicidade',        amount: 800,   days_ago: 9 },
  { desc: 'Laboratório prótese – pedido #248',   cat: 'Laboratório de Prótese',         amount: 1_800, days_ago: 4 },
  { desc: 'Conta de água – Fev/Mar',             cat: 'Energia e Água',                 amount: 320,   days_ago: 14 },
  # Mês passado
  { desc: 'Aluguel do consultório – Fevereiro',  cat: 'Aluguel',                         amount: 5_800, days_ago: 32 },
  { desc: 'Folha de pagamento – Fevereiro',      cat: 'Salários e Encargos',             amount: 12_500, days_ago: 35 },
  { desc: 'Autoclave nova (parcela 3/12)',        cat: 'Manutenção de Equipamentos',     amount: 1_250, days_ago: 38 },
  { desc: 'Materiais ortodontia (brackets)',      cat: 'Materiais Odontológicos',        amount: 2_100, days_ago: 40 }
]

expenses_paid_data.each do |data|
  paid_date = today - data[:days_ago].days
  cat = expense_cats.find { |c| c.name == data[:cat] }

  AccountTransaction.find_or_create_by!(
    account: account,
    description: data[:desc],
    entry_type: 'saida'
  ) do |txn|
    txn.financial_category = cat
    txn.bank_account = bank_accounts.sample
    txn.registered_by = admin
    txn.amount = data[:amount]
    txn.status = 'pago'
    txn.payment_method = payment_methods.sample
    txn.paid_at = paid_date
    txn.competence_date = paid_date
    txn.due_date = paid_date
    txn.origin = 'manual'
  end
  txn_count += 1
end

# ── 5D. SAÍDAS PENDENTES (a pagar) ─────────────────────────────────────────
payables_data = [
  { desc: 'Aluguel do consultório – Abril',       cat: 'Aluguel',                       amount: 5_800, due_days: 5 },
  { desc: 'Folha de pagamento – Abril',           cat: 'Salários e Encargos',            amount: 12_500, due_days: 5 },
  { desc: 'Laboratório prótese – pedido #250',   cat: 'Laboratório de Prótese',         amount: 2_600, due_days: 10 },
  { desc: 'ISS + Simples Nacional – Março',      cat: 'Impostos e Tributos',            amount: 2_800, due_days: -3 },
  { desc: 'Conta de luz – Março/Abril',          cat: 'Energia e Água',                 amount: 950,   due_days: 8 },
  { desc: 'Autoclave nova (parcela 4/12)',        cat: 'Manutenção de Equipamentos',     amount: 1_250, due_days: 15 },
  { desc: 'Resina + Cimento ionomérico',         cat: 'Materiais Odontológicos',        amount: 1_350, due_days: 0 },
  { desc: 'Google Ads – campanha Abril',          cat: 'Marketing e Publicidade',        amount: 1_500, due_days: 12 }
]

payables_data.each do |data|
  due = today + data[:due_days].days
  cat = expense_cats.find { |c| c.name == data[:cat] }

  AccountTransaction.find_or_create_by!(
    account: account,
    description: data[:desc],
    entry_type: 'saida'
  ) do |txn|
    txn.financial_category = cat
    txn.bank_account = bank_accounts.first
    txn.registered_by = admin
    txn.amount = data[:amount]
    txn.status = 'pendente'
    txn.payment_method = payment_methods.sample
    txn.due_date = due
    txn.competence_date = due.beginning_of_month
    txn.origin = 'manual'
  end
  txn_count += 1
end

puts "   ✅ #{txn_count} transações financeiras"

# ═══════════════════════════════════════════════════════════════════════════════
# 6. DESPESAS RECORRENTES
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n🔄 Criando despesas recorrentes..."

recurring_data = [
  { desc: 'Aluguel do Consultório',   cat: 'Aluguel',                   amount: 5_800, due_day: 5,  freq: 'monthly' },
  { desc: 'Folha de Pagamento',       cat: 'Salários e Encargos',       amount: 12_500, due_day: 5, freq: 'monthly' },
  { desc: 'Licença Software Gestão',  cat: 'Software e Tecnologia',     amount: 299,   due_day: 10, freq: 'monthly' },
  { desc: 'Internet Fibra',           cat: 'Despesas Operacionais',     amount: 189,   due_day: 15, freq: 'monthly' },
  { desc: 'Seguro do Consultório',    cat: 'Despesas Operacionais',     amount: 450,   due_day: 20, freq: 'monthly' },
  { desc: 'Autoclave (parcela)',      cat: 'Manutenção de Equipamentos', amount: 1_250, due_day: 25, freq: 'monthly' }
]

recurring_data.each do |data|
  cat = expense_cats.find { |c| c.name == data[:cat] }
  RecurringExpense.find_or_create_by!(account: account, description: data[:desc]) do |re|
    re.financial_category = cat
    re.bank_account = bank_accounts.first
    re.registered_by = admin
    re.amount = data[:amount]
    re.frequency = data[:freq]
    re.due_day = data[:due_day]
    re.competence_rule = 'same_month'
    re.start_date = today.beginning_of_year
    re.active = true
    re.payment_method = 'boleto'
  end
end

puts "   ✅ #{recurring_data.size} despesas recorrentes"

# ═══════════════════════════════════════════════════════════════════════════════
# 7. REGRAS DE COMISSÃO
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n📊 Criando regras de comissão..."

commission_data = [
  { cat: 'Consultas', type: 'percentage_received', value: 30 },
  { cat: 'Procedimentos Estéticos', type: 'percentage_received', value: 40 },
  { cat: 'Ortodontia', type: 'percentage_received', value: 35 },
  { cat: 'Implantes', type: 'percentage_received', value: 45 },
  { cat: 'Endodontia', type: 'percentage_received', value: 35 },
  { cat: nil, type: 'percentage_received', value: 25 }
]

commission_data.each do |data|
  cat = data[:cat] ? income_cats.find { |c| c.name == data[:cat] } : nil
  CommissionRule.find_or_create_by!(
    account: account,
    professional: admin,
    financial_category: cat,
    procedure_name: nil
  ) do |cr|
    cr.commission_type = data[:type]
    cr.value = data[:value]
    cr.active = true
    cr.valid_from = today.beginning_of_year
  end
end

puts "   ✅ #{commission_data.size} regras de comissão"

# ═══════════════════════════════════════════════════════════════════════════════
# RESUMO
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n" + '═' * 60
puts '🎉 SEED COMPLETO!'
puts '═' * 60
puts "   🏦 #{BankAccount.where(account: account).count} contas bancárias"
puts "   📂 #{FinancialCategory.where(account: account).count} categorias financeiras"
puts "   👥 #{Patient.where(account: account).active.count} pacientes ativos"
puts "   📅 #{PatientAppointment.where(account: account).active.count} agendamentos"
puts "   💰 #{AccountTransaction.where(account: account).kept.count} transações"
puts "   🔄 #{RecurringExpense.where(account: account).count} despesas recorrentes"
puts "   📊 #{CommissionRule.where(account: account).count} regras de comissão"
puts '═' * 60
puts "\n   Abra o dashboard financeiro e veja tudo preenchido! 🚀"
