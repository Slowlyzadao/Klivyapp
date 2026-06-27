# Perfil do paciente — campos editáveis pelo próprio paciente (PRD §10).
#
# Whitelist deliberada: paciente NÃO edita patient_status, responsible_professional_id,
# needs_recall, contact_id, custom_attributes — controlado pela clínica.
class Api::V1::PatientPortal::ProfileController < Api::V1::PatientPortal::BaseController
  EDITABLE = %i[name email phone birthdate sex address contact_preferences].freeze

  def show
    render json: { data: serialize(current_patient) }
  end

  def update
    attrs = profile_params
    return render_error('Nada para atualizar.') if attrs.empty?

    if current_patient.update(attrs)
      # Espelha mudanças no Contact (email/phone) para manter login funcional
      sync_contact!(attrs)

      log!('update', current_patient, metadata: { fields: attrs.keys })
      render json: { data: serialize(current_patient.reload) }
    else
      render_error(current_patient.errors.full_messages.join('; '))
    end
  end

  private

  def profile_params
    raw = params.slice(*EDITABLE).permit(*EDITABLE, address: {}, contact_preferences: {}).to_h
    # Strip strings vazias — usuário limpando campo
    raw.transform_values { |v| v.is_a?(String) ? v.strip.presence : v }.compact
  end

  def sync_contact!(attrs)
    return unless current_patient.contact

    contact_updates = attrs.slice(:email).dup
    contact_updates[:phone_number] = attrs[:phone] if attrs.key?(:phone)
    return if contact_updates.empty?

    current_patient.contact.update(contact_updates)
  rescue StandardError => e
    Rails.logger.warn("[ProfileController] sync_contact falhou: #{e.message}")
  end

  def serialize(p)
    {
      id:                  p.id,
      name:                p.name,
      email:               p.email,
      phone:               p.phone,
      birthdate:           p.birthdate,
      sex:                 p.sex,
      address:             p.address || {},
      contact_preferences: p.contact_preferences || {},
      account: { id: current_account.id, name: current_account.name }
    }
  end

  def log!(action, resource, metadata: {})
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: resource,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: metadata
    )
  end
end
