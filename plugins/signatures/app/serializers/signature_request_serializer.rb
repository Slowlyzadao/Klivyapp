# Serializa SignatureRequest pro JSON da API.
class SignatureRequestSerializer
  def initialize(request)
    @request = request
  end

  def as_json(include_audit: false, **)
    base = {
      id: @request.id,
      account_id: @request.account_id,
      signable_type: @request.signable_type,
      signable_id: @request.signable_id,
      requested_by_user_id: @request.requested_by_user_id,
      provider: @request.provider,
      external_id: @request.external_id,
      signing_url: @request.signing_url,
      status: @request.status,
      terminal: @request.terminal?,
      signer_name: @request.signer_name,
      signer_email: @request.signer_email,
      signer_phone: @request.signer_phone,
      signer_cpf: @request.signer_cpf,
      sent_at: @request.sent_at,
      viewed_at: @request.viewed_at,
      signed_at: @request.signed_at,
      completed_at: @request.completed_at,
      cancelled_at: @request.cancelled_at,
      expires_at: @request.expires_at,
      original_pdf_hash: @request.original_pdf_hash,
      signed_pdf_hash: @request.signed_pdf_hash,
      created_at: @request.created_at,
      updated_at: @request.updated_at
    }
    base[:audit_log] = @request.audit_log if include_audit
    base
  end
end
