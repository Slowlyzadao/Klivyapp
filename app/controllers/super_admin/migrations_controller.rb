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

    if kind == 'patients'
      handle_patients_create(account)
    else
      handle_single_file_create(account, kind)
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conta não encontrada.' }, status: :not_found
  end

  private

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
