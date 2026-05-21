class Api::V1::Accounts::PatientsController < Api::V1::Accounts::BaseController
  include BeclinicErrorResponse

  before_action :fetch_patient, only: [:show, :update, :destroy, :summary, :status, :quick_action, :change_history]
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/patients
  def index
    @patients = policy_scope(Patient)
                .active
                .includes(
                  :critical_alerts,
                  :responsible_professional,
                  :patient_appointments,
                  # avatar.attached? em resolved_avatar_url consulta active_storage
                  # — sem preload, vira N+1 (1 query por paciente).
                  avatar_attachment: :blob
                )

    @patients = filter_patients(@patients)
    @patients = apply_sort(@patients, params[:sort])
    @patients = @patients.page(page_number).per(page_size)

    # Pre-compute last AgendaEvent per contact_id in one query (avoids N+1)
    contact_ids = @patients.filter_map(&:contact_id).uniq
    @last_visits = if contact_ids.any?
                     AgendaEvent
                       .where(contact_id: contact_ids, account_id: Current.account.id)
                       .where('starts_at < ?', Time.current)
                       .group(:contact_id)
                       .maximum(:starts_at)
                   else
                     {}
                   end

    patient_ids = @patients.map(&:id)
    @procedures_counts = preload_procedures_counts(patient_ids)
    @balances_due_cents = preload_balances_due_cents(patient_ids)

    render 'api/v1/accounts/patients/index', format: :json
  end

  # GET /api/v1/accounts/:account_id/patients/:id
  def show
    log_patient_view
    render 'api/v1/accounts/patients/show', format: :json
  end

  # POST /api/v1/accounts/:account_id/patients
  def create
    @patient = Patient.new(patient_params.merge(account: Current.account))

    authorize @patient

    # Validate first — avoid creating orphan contacts if patient is invalid
    unless @patient.valid?
      return render json: { errors: @patient.errors.full_messages }, status: :unprocessable_entity
    end

    if @patient.contact_id.blank?
      formatted_phone = nil
      if @patient.phone.present?
        formatted_phone = @patient.phone.gsub(/\D/, '')
        formatted_phone = "+55#{formatted_phone}" unless formatted_phone.blank? || formatted_phone.start_with?('+')
      end

      contact = Current.account.contacts.find_by(phone_number: formatted_phone) if formatted_phone.present?
      contact ||= Current.account.contacts.create(
        name: @patient.name,
        email: @patient.email,
        phone_number: formatted_phone
      )

      @patient.contact_id = contact.id if contact&.persisted?
    end

    if @patient.save
      PatientAuditLog.log!(
        account: Current.account,
        patient: @patient,
        action: 'create',
        actor: current_user,
        ip_address: request.remote_ip
      )
      render 'api/v1/accounts/patients/show', format: :json, status: :created
    else
      render json: { errors: @patient.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/accounts/:account_id/patients/:id
  def update
    @patient.avatar.purge if patient_params[:avatar].present? && @patient.avatar.attached?

    if @patient.update(patient_params)
      PatientAuditLog.log!(
        account: Current.account,
        patient: @patient,
        action: 'update',
        actor: current_user,
        resource: @patient,
        changes: @patient.previous_changes,
        ip_address: request.remote_ip
      )
      render 'api/v1/accounts/patients/show', format: :json
    else
      render json: { errors: @patient.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/accounts/:account_id/patients/:id
  def destroy
    authorize @patient

    PatientAuditLog.log!(
      account: Current.account,
      patient: @patient,
      action: 'delete',
      actor: current_user,
      resource: @patient,
      ip_address: request.remote_ip
    )
    @patient.soft_delete!
    head :ok
  end

  # GET /api/v1/accounts/:account_id/patients/archived
  def archived
    @patients = Current.account.patients.deleted
                               .includes(:critical_alerts, :responsible_professional)
                               .order(:name)
    if params[:q].present?
      q = "%#{params[:q]}%"
      @patients = @patients.where('patients.name ILIKE :q OR patients.email ILIKE :q', q: q)
    end
    @patients = @patients.page(page_number).per(page_size)
    @last_visits = {}
    render 'api/v1/accounts/patients/index', format: :json
  end

  # PATCH /api/v1/accounts/:account_id/patients/:id/restore
  def restore
    @patient = Current.account.patients.deleted.find(params[:id])
    @patient.update!(deleted_at: nil)
    PatientAuditLog.log!(
      account: Current.account,
      patient: @patient,
      action: 'update',
      actor: current_user,
      resource: @patient,
      changes: { deleted_at: [Time.current, nil] },
      ip_address: request.remote_ip
    )
    render 'api/v1/accounts/patients/show', format: :json
  rescue ActiveRecord::RecordNotFound
    render_error('Paciente arquivado não encontrado', status: :not_found)
  end

  # GET /api/v1/accounts/:account_id/patients/by_contact?contact_id=X
  def by_contact
    @patient = Current.account.patients.active.find_by(contact_id: params[:contact_id])

    # Fallback por telefone: o paciente pode ter sido cadastrado em momento
    # separado da criação do contato (ex: cadastrado manualmente antes da
    # primeira mensagem WhatsApp), o que deixa `patient.contact_id` apontando
    # para um contato duplicado com o mesmo telefone. Auto-repara quando o
    # paciente encontrado está sem contato vinculado — se já aponta para
    # outro contato, não sobrescreve (caso intencional: família/twin
    # compartilhando telefone exige decisão humana via merge de contatos).
    @patient ||= find_patient_by_contact_phone(params[:contact_id])

    return render_error('Paciente não encontrado', status: :not_found) unless @patient

    authorize @patient
    @last_appointment = last_appointment_for(@patient)
    @next_appointment = next_appointment_for(@patient)
    @urgent_consents  = []

    render 'api/v1/accounts/patients/summary', format: :json
  end

  # GET /api/v1/accounts/:account_id/patients/:id/summary
  # Endpoint estrela — payload consolidado do prontuário
  def summary
    log_patient_view
    @last_appointment = last_appointment_for(@patient)
    @next_appointment = next_appointment_for(@patient)
    @urgent_consents  = [] # será populado pelo Bloco 5 (ConsentRecord)

    render 'api/v1/accounts/patients/summary', format: :json
  end


  # PATCH /api/v1/accounts/:account_id/patients/:id/status
  def status
    new_status = params[:patient_status]

    return render_error('Status inválido') unless Patient.patient_statuses.key?(new_status)

    if @patient.update(patient_status: new_status)
      PatientAuditLog.log!(
        account: Current.account,
        patient: @patient,
        action: 'update',
        actor: current_user,
        resource: @patient,
        changes: { patient_status: [@patient.patient_status_was, new_status] },
        ip_address: request.remote_ip
      )
      render json: { patient_status: @patient.patient_status }, status: :ok
    else
      render_error(@patient.errors.full_messages)
    end
  end

  # POST /api/v1/accounts/:account_id/patients/:id/quick_action
  def quick_action
    case params[:action_type]
    when 'mark_no_show'
      handle_no_show
    when 'toggle_recall'
      @patient.update!(needs_recall: !@patient.needs_recall)
      render json: { needs_recall: @patient.needs_recall }, status: :ok
    else
      render_error('Ação desconhecida')
    end
  end

  # GET /api/v1/accounts/:account_id/patients/:id/change_history
  def change_history
    @audit_logs = PatientAuditLog
                  .where(patient: @patient)
                  .where(action: %w[update create])
                  .order(occurred_at: :desc)
                  .page(page_number)
                  .per(page_size)

    render 'api/v1/accounts/patients/change_history', format: :json
  end

  private

  def fetch_patient
    @patient = Current.account.patients.find(params[:id])
    authorize @patient
  rescue ActiveRecord::RecordNotFound
    render_error('Paciente não encontrado', status: :not_found)
  end

  def patient_params
    params.require(:patient).permit(
      :name, :social_name, :phone, :email, :cpf, :rg, :birthdate, :sex, :marital_status,
      :patient_status, :pinned_note, :notes, :origin, :unit,
      :has_guardian,
      :responsible_professional_id, :contact_id, :avatar_url, :avatar,
      :no_show_count, :needs_recall, :recall_dismissed_at,
      address: [:street, :number, :complement, :neighborhood, :city, :state, :zip_code, :country],
      emergency_contact: [:name, :phone, :relationship],
      guardian: [:name, :cpf, :phone, :relationship],
      insurance: [:name, :number, :plan, :validity],
      billing_info: {},
      contact_preferences: {},
      communication_opt_ins: {},
      lgpd_consent: [:accepted, :accepted_at, :version, :ip_address, :image_use_accepted],
      contacts: []
    )
  end

  def filter_patients(scope)
    scope = apply_search(scope, params[:q]) if params[:q].present?
    scope = scope.where(patient_status: params[:status]) if params[:status].present?
    scope = scope.where(responsible_professional_id: params[:professional_id]) if params[:professional_id].present?
    scope = scope.needs_recall if params[:needs_recall] == 'true'
    scope
  end

  SORT_OPTIONS = {
    'name_asc'        => { name: :asc },
    'name_desc'       => { name: :desc },
    'created_at_desc' => { created_at: :desc },
    'created_at_asc'  => { created_at: :asc }
  }.freeze

  def apply_sort(scope, sort_param)
    scope.order(SORT_OPTIONS.fetch(sort_param, name: :asc))
  end

  # Busca por nome e email (ILIKE) e — se a query contém >= 3 dígitos — também
  # por telefone e CPF. Usada pelo dropdown de "Telefone Principal" da Ficha
  # Cadastral para detectar pacientes existentes ao digitar um número.
  def apply_search(scope, query)
    q = query.to_s.strip
    digits = q.gsub(/\D/, '')

    if digits.length >= 3
      scope.where(
        'patients.name ILIKE :text OR patients.email ILIKE :text OR ' \
        'patients.phone LIKE :digits OR patients.cpf LIKE :digits',
        text: "%#{q}%", digits: "%#{digits}%"
      )
    else
      scope.where('patients.name ILIKE :text OR patients.email ILIKE :text', text: "%#{q}%")
    end
  end

  def log_patient_view
    PatientAuditLog.log!(
      account: Current.account,
      patient: @patient,
      action: 'view',
      actor: current_user,
      ip_address: request.remote_ip
    )
  end

  # Busca paciente por telefone do contato como fallback para `by_contact`.
  # Cobre o cenário em que paciente e contato existem mas não estão linkados
  # (cadastros feitos em momentos separados, find-by-phone do controller
  # falhando por formatação divergente, etc). Auto-repara o link só quando
  # `patient.contact_id` está nil — preserva links existentes intencionais.
  def find_patient_by_contact_phone(contact_id)
    return nil if contact_id.blank?

    contact = Current.account.contacts.find_by(id: contact_id)
    return nil if contact.nil? || contact.phone_number.blank?

    digits = contact.phone_number.gsub(/\D/, '')
    # Tira DDI 55 quando presente (E.164 BR tem 12 ou 13 dígitos com `+55`).
    core = digits.start_with?('55') && digits.length > 11 ? digits[2..] : digits
    return nil if core.length < 10

    patient = Current.account.patients.active
                              .where('patients.phone LIKE ?', "%#{core}%")
                              .first
    return nil unless patient

    patient.update_column(:contact_id, contact.id) if patient.contact_id.nil?
    patient
  end

  def last_appointment_for(patient)
    return nil unless patient.contact_id

    AgendaEvent
      .where(contact_id: patient.contact_id, account_id: Current.account.id)
      .where('starts_at < ?', Time.current)
      .order(starts_at: :desc)
      .first
  end

  def next_appointment_for(patient)
    return nil unless patient.contact_id

    AgendaEvent
      .where(contact_id: patient.contact_id, account_id: Current.account.id)
      .where('starts_at > ?', Time.current)
      .order(starts_at: :asc)
      .first
  end

  def handle_no_show
    # Captura valores ANTES da mutação pra registrar diff correto no audit log.
    previous_no_show_count = @patient.no_show_count
    previous_status = @patient.patient_status

    # Transação garante que increment + update_status + audit log ou todos passam
    # ou nenhum, evitando estado inconsistente (ex: contador subiu mas status
    # não virou 'faltoso' porque um deles falhou).
    ActiveRecord::Base.transaction do
      @patient.increment!(:no_show_count)

      if @patient.no_show_count >= 3 && !@patient.patient_status_faltoso?
        @patient.update!(patient_status: 'faltoso')
      end

      audit_changes = { no_show_count: [previous_no_show_count, @patient.no_show_count] }
      audit_changes[:patient_status] = [previous_status, @patient.patient_status] if previous_status != @patient.patient_status

      PatientAuditLog.log!(
        account: Current.account,
        patient: @patient,
        action: 'update',
        actor: current_user,
        resource: @patient,
        changes: audit_changes,
        ip_address: request.remote_ip
      )
    end

    render json: { no_show_count: @patient.no_show_count, patient_status: @patient.patient_status }, status: :ok
  end

  # Procedimentos realizados = SessionLog ativos (canon: aba "Evolução >
  # Ficha Clínica" do prontuário). Pré-carregado em 1 query agregada para
  # evitar N+1 nas linhas da listagem.
  def preload_procedures_counts(patient_ids)
    return {} if patient_ids.empty?

    SessionLog.where(patient_id: patient_ids, account_id: Current.account.id)
              .where(deleted_at: nil)
              .group(:patient_id)
              .count
  end

  # Saldo financeiro em aberto = soma de (amount - received) das parcelas
  # `pendente|vencido|parcial` do paciente (Financial::Installment v2). Inclui
  # vencidas porque o usuário cobra/negocia pelo valor total devido.
  def preload_balances_due_cents(patient_ids)
    return {} if patient_ids.empty?

    Financial::Installment
      .where(patient_id: patient_ids, account_id: Current.account.id)
      .where(status: %w[pendente vencido parcial])
      .group(:patient_id)
      .sum('amount_cents - received_amount_cents')
  end

  def page_number
    params[:page] || 1
  end

  def page_size
    [params[:per_page].to_i, 500].min.then { |n| n.zero? ? 25 : n }
  end
end
