class SuperAdmin::MigrationsController < SuperAdmin::ApplicationController
  MAX_FILE_SIZE = 25.megabytes

  def index
    respond_to do |format|
      format.html { render :index }
      format.json do
        render json: {
          accounts: Account.order(:id).limit(500).select(:id, :name).map { |a| { id: a.id, name: a.name } },
          runs: MigrationRun.recent.limit(50).map { |r| serialize_run(r) }
        }
      end
    end
  end

  def show
    run = MigrationRun.find(params[:id])
    render json: serialize_run(run)
  end

  def create
    account = Account.find(params[:account_id])
    kind    = params[:kind].to_s

    return render json: { error: 'Tipo de migração inválido.' }, status: :unprocessable_entity unless MigrationRun::KINDS.include?(kind)

    case kind
    when 'patients'
      handle_patients_create(account)
    when 'treatment_operations'
      handle_treatment_operations_create(account)
    when 'financial'
      handle_financial_create(account)
    else
      handle_single_file_create(account, kind)
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conta não encontrada.' }, status: :not_found
  end

  # Read-only "what would happen if I imported this CSV" — runs the same
  # parse/match/decide logic as create but doesn't touch the DB. Used by the
  # frontend to show a preview table before the user clicks "Iniciar".
  def preview
    account = Account.find(params[:account_id])
    kind    = params[:kind].to_s

    return render json: { error: 'Tipo de migração inválido.' }, status: :unprocessable_entity unless MigrationRun::KINDS.include?(kind)

    case kind
    when 'patients'
      render json: preview_patients(account)
    when 'treatment_operations'
      render json: preview_treatment_operations(account)
    when 'financial'
      render json: preview_financial(account)
    else
      render json: { error: "Pré-visualização ainda não disponível para kind=#{kind}." }, status: :not_implemented
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conta não encontrada.' }, status: :not_found
  rescue StandardError => e
    render json: { error: "#{e.class}: #{e.message}" }, status: :unprocessable_entity
  end

  # Lista de usuários da conta pra mapear "DentistName" → user_id no fluxo de
  # importação de TreatmentOperation. Inclui klivy_role.name (ex. "especialista")
  # pra o admin reconhecer quem é profissional clínico.
  #
  # Partimos de AccountUser (não User) porque User tem coluna tipo `json`
  # (custom_attributes/pubsub_token etc.) e `User.distinct.joins(:account_users)`
  # explode com `PG::UndefinedFunction: equality operator for type json`.
  # AccountUser→User é 1:1 dentro da conta (unique index), não precisa distinct.
  def professional_users
    account = Account.find(params[:account_id])
    account_users = AccountUser.where(account_id: account.id)
                               .includes(:user, :klivy_role)
                               .joins(:user)
                               .merge(User.order(:name))

    payload = account_users.map do |au|
      next nil if au.user.nil?

      {
        id: au.user.id,
        name: au.user.available_name || au.user.name,
        email: au.user.email,
        klivy_role: au.klivy_role&.name
      }
    end.compact

    render json: { users: payload }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conta não encontrada.' }, status: :not_found
  end

  # F-10 Importador Financeiro: lista PaymentMethods + BankAccounts + DreCategories
  # ATIVOS da conta destino. Usado pelo form do admin pra mapear:
  #   - "kind Clinicorp → PaymentMethod Klivy"
  #   - "Specialty Clinicorp → DreCategory Klivy"
  #   - escolher BankAccount específica
  # Tudo num único round-trip pra evitar 3 requests do frontend.
  def payment_methods
    account = Account.find(params[:account_id])
    methods = Financial::PaymentMethod.where(account_id: account.id, status: 'active')
                                      .order(:kind, :name)
                                      .pluck(:id, :kind, :name, :provider, :provider_alias)
                                      .map do |id, kind, name, provider, provider_alias|
      { id: id, kind: kind, name: name, provider: provider, provider_alias: provider_alias }
    end

    bank_accounts = Financial::BankAccount.where(account_id: account.id, active: true)
                                          .order(:id)
                                          .pluck(:id, :name, :kind)
                                          .map { |id, name, kind| { id: id, name: name, kind: kind } }

    dre_categories = Financial::DreCategory.where(account_id: account.id, kind: 'receita')
                                            .order(:path, :name)
                                            .pluck(:id, :name, :path)
                                            .map { |id, name, path| { id: id, name: name, path: path } }

    render json: {
      payment_methods: methods,
      bank_accounts: bank_accounts,
      dre_categories: dre_categories
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conta não encontrada.' }, status: :not_found
  end

  private

  def preview_treatment_operations(account)
    operations_file = params[:csv_operations] || params[:csv]
    raise 'Arquivo de Operações é obrigatório.' if operations_file.blank?
    raise "Arquivo '#{operations_file.original_filename}' excede o limite de #{MAX_FILE_SIZE / 1.megabyte}MB." \
      if operations_file.size.to_i > MAX_FILE_SIZE

    Migration::ClinicorpTreatmentOperationPreviewer.new(
      account,
      operations_csv: read_file(operations_file),
      dentist_mapping: parse_dentist_mapping
    ).call
  end

  def handle_treatment_operations_create(account)
    operations_file = params[:csv_operations] || params[:csv]
    return render json: { error: 'Arquivo de Operações (TreatmentOperation.csv) é obrigatório.' }, status: :unprocessable_entity if operations_file.blank?
    return render json: { error: "Arquivo excede o limite de #{MAX_FILE_SIZE / 1.megabyte}MB." }, status: :unprocessable_entity \
      if operations_file.size.to_i > MAX_FILE_SIZE

    payload = {
      operations: read_file(operations_file),
      dentist_mapping: parse_dentist_mapping
    }

    run = MigrationRun.create!(
      account_id: account.id,
      kind: 'treatment_operations',
      source: params[:source].presence || 'clinicorp',
      csv_filename: operations_file.original_filename,
      triggered_by_super_admin_id: current_super_admin&.id
    )

    Migration::ProcessCsvJob.perform_later(run.id, payload)

    render json: serialize_run(run), status: :created
  end

  # F-10 Importador Financeiro Clinicorp.
  # 3 arquivos: Budgets.csv + PaymentHeader.csv + PaymentItem.csv.
  # `bank_account_strategy`: 'create' (cria conta dedicada) ou 'existing'
  # (usa primeira conta ativa da clínica; erro se não houver).
  def preview_financial(account)
    budgets_file  = params[:csv_budgets]
    headers_file  = params[:csv_payment_headers]
    items_file    = params[:csv_payment_items]

    raise 'Arquivo de Orçamentos (Budgets) é obrigatório.' if budgets_file.blank?
    raise 'Arquivo de Cobranças (PaymentHeader) é obrigatório.' if headers_file.blank?
    raise 'Arquivo de Parcelas (PaymentItem) é obrigatório.' if items_file.blank?

    [budgets_file, headers_file, items_file].each do |f|
      raise "Arquivo '#{f.original_filename}' excede o limite de #{MAX_FILE_SIZE / 1.megabyte}MB." if f.size.to_i > MAX_FILE_SIZE
    end

    Migration::ClinicorpFinancialPreviewer.new(
      account,
      budgets_csv: read_file(budgets_file),
      payment_headers_csv: read_file(headers_file),
      payment_items_csv: read_file(items_file),
      dentist_mapping: parse_dentist_mapping,
      bank_account_strategy: params[:bank_account_strategy].presence || 'create',
      bank_account_id: params[:bank_account_id].presence,
      payment_method_mapping: parse_payment_method_mapping,
      specialty_mapping: parse_specialty_mapping
    ).call
  end

  def handle_financial_create(account)
    budgets_file = params[:csv_budgets]
    headers_file = params[:csv_payment_headers]
    items_file   = params[:csv_payment_items]

    return render json: { error: 'Arquivo de Orçamentos (Budgets) é obrigatório.' }, status: :unprocessable_entity if budgets_file.blank?
    return render json: { error: 'Arquivo de Cobranças (PaymentHeader) é obrigatório.' }, status: :unprocessable_entity if headers_file.blank?
    return render json: { error: 'Arquivo de Parcelas (PaymentItem) é obrigatório.' }, status: :unprocessable_entity if items_file.blank?

    [budgets_file, headers_file, items_file].each do |f|
      return render json: { error: "Arquivo '#{f.original_filename}' excede o limite de #{MAX_FILE_SIZE / 1.megabyte}MB." }, status: :unprocessable_entity if f.size.to_i > MAX_FILE_SIZE
    end

    payload = {
      budgets: read_file(budgets_file),
      payment_headers: read_file(headers_file),
      payment_items: read_file(items_file),
      dentist_mapping: parse_dentist_mapping,
      bank_account_strategy: params[:bank_account_strategy].presence || 'create',
      bank_account_id: params[:bank_account_id].presence,
      payment_method_mapping: parse_payment_method_mapping,
      specialty_mapping: parse_specialty_mapping
    }

    run = MigrationRun.create!(
      account_id: account.id,
      kind: 'financial',
      source: params[:source].presence || 'clinicorp',
      csv_filename: [budgets_file.original_filename, headers_file.original_filename, items_file.original_filename].join(' + '),
      triggered_by_super_admin_id: current_super_admin&.id
    )

    Migration::ProcessCsvJob.perform_later(run.id, payload)

    render json: serialize_run(run), status: :created
  end

  # Aceita `dentist_mapping` como Hash JSON ou string JSON (FormData não tem
  # nested params nativos). Frontend manda como string JSON-encoded.
  def parse_dentist_mapping
    raw = params[:dentist_mapping]
    return {} if raw.blank?

    return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return raw if raw.is_a?(Hash)

    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
  end

  # Igual ao parse_dentist_mapping mas pra `payment_method_mapping` (F-10):
  # ex { "pix" => 42, "credito" => 43 }. Frontend manda JSON-encoded.
  def parse_payment_method_mapping
    raw = params[:payment_method_mapping]
    return {} if raw.blank?

    return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return raw if raw.is_a?(Hash)

    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
  end

  # F-10 `specialty_mapping`: ex { "Cirurgia" => 453, "Endodontia" => 451 }.
  # Vincula Specialty Clinicorp → DreCategory.id pra preencher
  # `financial_dre_category_id` nas Installments/Entries criadas.
  def parse_specialty_mapping
    raw = params[:specialty_mapping]
    return {} if raw.blank?

    return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    return raw if raw.is_a?(Hash)

    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
  end

  def preview_patients(account)
    patients_file          = params[:csv_patients] || params[:csv]
    patient_anamnesis_file = params[:csv_patient_anamnesis]
    anamnesis_file         = params[:csv_anamnesis]

    raise 'Arquivo de Pacientes é obrigatório.' if patients_file.blank?
    [patients_file, patient_anamnesis_file, anamnesis_file].compact.each do |f|
      raise "Arquivo '#{f.original_filename}' excede o limite de #{MAX_FILE_SIZE / 1.megabyte}MB." if f.size.to_i > MAX_FILE_SIZE
    end

    Migration::ClinicorpPatientPreviewer.new(
      account,
      patients_csv: read_file(patients_file),
      patient_anamnesis_csv: patient_anamnesis_file ? read_file(patient_anamnesis_file) : nil,
      anamnesis_csv: anamnesis_file ? read_file(anamnesis_file) : nil
    ).call
  end

  def handle_patients_create(account)
    patients_file          = params[:csv_patients] || params[:csv]  # accept legacy field name
    patient_anamnesis_file = params[:csv_patient_anamnesis]
    anamnesis_file         = params[:csv_anamnesis]

    return render json: { error: 'Arquivo de Pacientes (Patient.csv) é obrigatório.' }, status: :unprocessable_entity if patients_file.blank?

    [patients_file, patient_anamnesis_file, anamnesis_file].compact.each do |f|
      return render json: { error: "Arquivo '#{f.original_filename}' excede o limite de #{MAX_FILE_SIZE / 1.megabyte}MB." }, status: :unprocessable_entity if f.size.to_i > MAX_FILE_SIZE
    end

    payload = {
      patients:          read_file(patients_file),
      patient_anamnesis: patient_anamnesis_file ? read_file(patient_anamnesis_file) : nil,
      anamnesis:         anamnesis_file ? read_file(anamnesis_file) : nil
    }

    run = MigrationRun.create!(
      account_id: account.id,
      kind: 'patients',
      source: params[:source].presence || 'clinicorp',
      csv_filename: patients_file.original_filename,
      triggered_by_super_admin_id: current_super_admin&.id
    )

    Migration::ProcessCsvJob.perform_later(run.id, payload)

    render json: serialize_run(run), status: :created
  end

  def handle_single_file_create(account, kind)
    file = params[:csv]
    return render json: { error: 'Arquivo CSV é obrigatório.' }, status: :unprocessable_entity if file.blank?
    return render json: { error: "Arquivo excede o limite de #{MAX_FILE_SIZE / 1.megabyte}MB." }, status: :unprocessable_entity if file.size.to_i > MAX_FILE_SIZE

    csv_content = read_file(file)

    run = MigrationRun.create!(
      account_id: account.id,
      kind: kind,
      source: params[:source].presence || 'clinicorp',
      csv_filename: file.original_filename,
      triggered_by_super_admin_id: current_super_admin&.id
    )

    Migration::ProcessCsvJob.perform_later(run.id, csv_content)

    render json: serialize_run(run), status: :created
  end

  def read_file(file)
    raw = file.respond_to?(:read) ? file.read : File.read(file.path)
    raw.force_encoding('UTF-8')
    raw.valid_encoding? ? raw : raw.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
  end

  def serialize_run(run)
    {
      id: run.id,
      account_id: run.account_id,
      account_name: run.account&.name,
      kind: run.kind,
      source: run.source,
      status: run.status,
      csv_filename: run.csv_filename,
      total_rows: run.total_rows,
      processed_rows: run.processed_rows,
      created_count: run.created_count,
      updated_count: run.updated_count,
      skipped_count: run.skipped_count,
      error_count: run.error_count,
      progress_percent: run.progress_percent,
      errors_log: run.errors_log,
      error_message: run.error_message,
      started_at: run.started_at,
      finished_at: run.finished_at,
      created_at: run.created_at
    }
  end
end
