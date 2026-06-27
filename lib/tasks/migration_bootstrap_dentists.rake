# Cria User + AccountUser + klivy_role (Especialista) pros DentistName únicos
# de um (ou vários) CSV de Appointment exportado do Clinicorp, vinculando à
# Account de destino.
#
# Contexto:
# A importação de Agenda usa `Migration::ClinicorpAgendaImporter#find_user`
# (clinicorp_agenda_importer.rb:319) pra resolver `user_id` por match de nome:
#
#     candidate = @account.users.find { |u| normalize(u.name) == norm }
#
# Se o dentista não está cadastrado no Klivy ANTES do import, todo evento
# fica com `user_id: nil` (caso conta 12274 Streit 2026-05-21 — 19.967
# eventos sem vínculo). Re-importar com idempotência (`source=clinicorp +
# external_id`) atualiza `user_id` quando os Users já existem, mas alguém
# precisa cadastrá-los primeiro.
#
# Esta rake task automatiza esse pré-passo: lê os DentistName únicos do CSV,
# cria os Users como placeholders (email `.local`, senha aleatória, password
# reset obrigatório) e atribui `klivy_role` "Especialista" (preset clínico).
#
# Multi-tenant: scope obrigatório por `account_id` no argumento.
# Idempotente: re-rodar pula Users que já existem (match por email OU nome
# normalizado dentro da conta).
#
# Uso:
#   bundle exec rails 'migration:bootstrap_dentists[12274,plugins/xls/clinica-streit/agendamentos/]'
#   DRY_RUN=true bundle exec rails 'migration:bootstrap_dentists[12274,/path/file.csv]'
#   MIN_EVENTS=50 bundle exec rails 'migration:bootstrap_dentists[12274,/path/dir/]'
#
# Opções via ENV:
#   DRY_RUN=true     — só lista o que faria, sem criar nada
#   MIN_EVENTS=N     — só cadastra dentistas com >= N eventos (filtra ruído)
#   EMAIL_SUFFIX=x   — sobrescreve sufixo do email placeholder (default: account-<id>.import.local)
#   ROLE=Especialista — sobrescreve klivy_role (default: Especialista)

namespace :migration do
  desc 'Cria dentistas a partir dos DentistName únicos de Appointment.csv (idempotente)'
  task :bootstrap_dentists, [:account_id, :csv_path] => :environment do |_t, args|
    account_id = args[:account_id].to_i
    csv_path   = args[:csv_path].to_s
    abort 'Uso: rails "migration:bootstrap_dentists[<account_id>,<csv_path_or_dir>]"' if account_id.zero? || csv_path.blank?

    account = Account.find(account_id)
    dry_run = ENV['DRY_RUN'] == 'true'
    min_events = ENV.fetch('MIN_EVENTS', '1').to_i
    email_suffix = ENV.fetch('EMAIL_SUFFIX', "account-#{account.id}.import.local")
    role_name = ENV.fetch('ROLE', 'Especialista')

    paths = expand_csv_paths(csv_path)
    abort "Nenhum CSV encontrado em '#{csv_path}'" if paths.empty?

    puts ''
    puts '=== Migration — Bootstrap Dentists ==='
    puts "Conta:        #{account.id} (#{account.name})"
    puts "Arquivos CSV: #{paths.size}"
    paths.each { |p| puts "  - #{p}" }
    puts "Modo:         #{dry_run ? 'DRY-RUN (sem alterações)' : 'APLICANDO'}"
    puts "Filtro:       MIN_EVENTS=#{min_events}"
    puts ''

    name_counts = aggregate_dentist_names(paths)
    candidates = name_counts.select { |_, c| c >= min_events }

    puts "Dentistas únicos encontrados: #{name_counts.size}"
    puts "Após filtro MIN_EVENTS=#{min_events}: #{candidates.size}"
    ignored = name_counts.size - candidates.size
    puts "Ignorados (< #{min_events} eventos): #{ignored}" if ignored.positive?
    puts ''

    role = account.klivy_roles.find_by(name: role_name)
    if role.nil?
      puts "⚠ KlivyRole '#{role_name}' não encontrada na conta #{account.id}. "
      puts '  Users vão ser criados sem klivy_role (apenas role=agent do AccountUser).'
      puts '  Pra criar os presets primeiro: bundle exec rails custom_roles:seed_presets'
    else
      puts "klivy_role alvo: '#{role.name}' (id=#{role.id})"
    end
    puts ''

    created = 0
    matched_existing = 0
    errors = 0

    candidates.sort_by { |_, c| -c }.each do |name, count|
      norm = normalize_name(name)
      existing_user = account.users.find { |u| normalize_name(u.name) == norm }

      if existing_user
        au = AccountUser.find_by(account_id: account.id, user_id: existing_user.id)
        puts "  #{count.to_s.rjust(5)}× #{name.ljust(45)} → existe (user_id=#{existing_user.id}, role=#{au&.klivy_role&.name || 'sem klivy_role'})"
        matched_existing += 1
        next
      end

      slug = name.parameterize.presence || "dentist-#{SecureRandom.hex(4)}"
      email = "dentist-#{slug}@#{email_suffix}"

      if dry_run
        puts "  #{count.to_s.rjust(5)}× #{name.ljust(45)} → CRIARIA (email=#{email})"
        next
      end

      begin
        ActiveRecord::Base.transaction do
          temp_password = generate_temp_password
          user = User.find_or_initialize_by(email: email)
          user.name = name
          user.password = temp_password
          user.password_confirmation = temp_password
          user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
          user.save!

          au = AccountUser.find_or_initialize_by(account_id: account.id, user_id: user.id)
          au.role = :agent
          au.klivy_role = role if role
          au.save!
        end
        puts "  #{count.to_s.rjust(5)}× #{name.ljust(45)} → criado (email=#{email})"
        created += 1
      rescue StandardError => e
        puts "  #{count.to_s.rjust(5)}× #{name.ljust(45)} → ERRO: #{e.class}: #{e.message}"
        errors += 1
      end
    end

    puts ''
    puts '=== Resumo ==='
    puts "  Criados:           #{created}"
    puts "  Já existiam:       #{matched_existing}"
    puts "  Erros:             #{errors}"
    puts "  Ignorados:         #{ignored}"
    puts "  Total candidatos:  #{candidates.size}"
    puts ''

    if dry_run
      puts 'Pra aplicar:'
      puts "  bundle exec rails 'migration:bootstrap_dentists[#{account.id},#{csv_path}]'"
    elsif created.positive?
      puts 'Próximo passo: re-rodar a importação de Agenda. O ClinicorpAgendaImporter'
      puts 'agora vai resolver `user_id` automaticamente via find_user(name normalizado)'
      puts 'e o branch de update (clinicorp_agenda_importer.rb:194) atualiza eventos'
      puts 'existentes via idempotência por external_id.'
    end
    puts ''
  end

  # Helpers ────────────────────────────────────────────────────────────────────

  def expand_csv_paths(path)
    if File.directory?(path)
      Dir.glob(File.join(path, '*.csv')).sort
    elsif File.file?(path)
      [path]
    else
      []
    end
  end

  def aggregate_dentist_names(paths)
    require 'csv'
    counts = Hash.new(0)
    paths.each do |p|
      delim = detect_delimiter(p)
      CSV.foreach(p, headers: true, col_sep: delim, liberal_parsing: true) do |row|
        name = row['DentistName'].to_s.strip
        next if name.blank?
        counts[name] += 1
      end
    end
    counts
  end

  def detect_delimiter(path)
    first_line = File.open(path, &:readline)
    { ',' => first_line.count(','), ';' => first_line.count(';'), "\t" => first_line.count("\t") }
      .max_by { |_, v| v }.first
  end

  def normalize_name(value)
    value.to_s.strip.downcase
  end

  # Senha temporária que atende a validação do Klivy
  # (config/initializers/secure_password.rb): >= 1 maiúscula, >= 1 minúscula,
  # >= 1 dígito, >= 1 especial. 28 chars random alphanumeric + 4 garantidos
  # (A, a, 1, !) embaralhados. Dentista precisa usar "Esqueci minha senha"
  # pra logar — esta senha NUNCA é exibida.
  def generate_temp_password
    alpha = SecureRandom.alphanumeric(28)
    required = %w[A a 1 !]
    (alpha.chars + required).shuffle.join
  end
end
