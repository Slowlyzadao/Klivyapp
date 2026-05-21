# Sprint L — factories pros modelos de teleconsulta (audio-only).
FactoryBot.define do
  factory :telemed_recording do
    status         { 'pending' }
    recording_kind { 'audio' }

    after(:build) do |rec|
      rec.account       ||= rec.agenda_event&.account || create(:account)
      rec.agenda_event  ||= create(:agenda_event, account: rec.account)
    end

    # 3 egress jobs ativos (doctor+patient isolated + composite). Status
    # `recording` é o passo após orchestrator.start! retornar started=true.
    trait :recording do
      status              { 'recording' }
      doctor_egress_id    { "EG_doctor_#{SecureRandom.hex(4)}" }
      patient_egress_id   { "EG_patient_#{SecureRandom.hex(4)}" }
      composite_egress_id { "EG_composite_#{SecureRandom.hex(4)}" }
    end

    # Webhook reportou que os 3 arquivos chegaram no R2. Próximo passo:
    # TranscribeRecordingJob.
    trait :uploaded do
      recording
      status              { 'uploaded' }
      doctor_audio_key    { 'accounts/1/telemed/1/2026/05/20/doctor-temp.ogg' }
      patient_audio_key   { 'accounts/1/telemed/1/2026/05/20/patient-temp.ogg' }
      composite_audio_key { 'accounts/1/telemed/1/2026/05/20/composite.ogg' }
      duration_seconds    { 1800 }
    end

    # Pós-transcribe: doctor/patient temps já deletados, composite permanece.
    trait :transcribed do
      uploaded
      status              { 'transcribed' }
      doctor_audio_key    { nil }
      patient_audio_key   { nil }
      transcript_text     { "[00:00:00] [Doutor] oi\n[00:00:02] [Paciente] oi" }
      transcript_segments { [{ start: 0, end: 2, speaker: 'Doutor', text: 'oi' }] }
      transcript_provider { 'whisper' }
    end

    trait :ready do
      transcribed
      status { 'ready' }
    end

    trait :failed do
      status         { 'failed' }
      failure_reason { 'falha simulada em teste' }
    end

    trait :archived do
      ready
      archived_at         { Time.current }
      composite_audio_key { nil }
    end
  end

  factory :proposed_evolution do
    provider { 'claude-sonnet-4-6' }
    status   { 'pending_review' }
    soap_structure {
      {
        'subjetivo' => 'paciente relata dor',
        'objetivo'  => 'desgaste em 36',
        'avaliacao' => 'hipersensibilidade dentinaria',
        'plano'     => 'fluor topico + retorno 15 dias'
      }
    }
    raw_markdown     { '## S — Subjetivo ...' }
    attention_points { [] }

    after(:build) do |evo|
      evo.telemed_recording ||= create(:telemed_recording, :ready)
    end

    trait :approved do
      status { 'approved' }
    end

    trait :rejected do
      status         { 'rejected' }
      reviewer_notes { 'paciente solicitou exclusao' }
    end
  end
end
