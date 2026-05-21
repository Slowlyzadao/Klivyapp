# Sprint L — Rake tasks pra testar o pipeline de teleconsulta localmente
# sem precisar de LiveKit Egress (Docker) nem R2 funcionando.
#
# Uso:
#
#   # 1. Simula uma teleconsulta COMPLETA (fake transcript + fake evolução).
#   #    Ideal pra testar UI/aprovação sem chaves de API.
#   bin/rails 'telemed:simulate[EVENT_ID]'
#
#   # 2. Lista AgendaEvents recentes da conta (pra escolher um pro simulate).
#   bin/rails 'telemed:list_events[ACCOUNT_ID]'
#
#   # 3. Habilita gravação na clínica (config patient_portal_setting).
#   bin/rails 'telemed:enable_recording[ACCOUNT_ID]'
#
#   # 4. Limpa tudo (gravações + propostas) pra começar do zero.
#   bin/rails 'telemed:reset[ACCOUNT_ID]'

namespace :telemed do
  FAKE_TRANSCRIPT = <<~TEXT.freeze
    [00:00:02] [Doutor] Bom dia, João, tudo bem? Conta pra mim o que tá te incomodando.
    [00:00:08] [Paciente] Bom dia, doutor. Faz umas duas semanas que tá doendo um dente do fundo do lado direito, principalmente quando bebo água gelada.
    [00:00:18] [Doutor] Entendi. A dor é constante ou só quando você bebe algo frio?
    [00:00:24] [Paciente] É só com o frio mesmo. Quente não dói nada.
    [00:00:30] [Doutor] Você tem alguma alergia a medicamento? Toma algum remédio atualmente?
    [00:00:36] [Paciente] Tenho alergia a penicilina, doutor. E só tomo remédio pra pressão, o losartana.
    [00:00:45] [Doutor] Perfeito. Pelo que você relata, é compatível com hipersensibilidade dentinária no 47 ou 46. Eu vou te receitar um dessensibilizante pra usar agora, e quero te ver presencialmente em 15 dias pra aplicar flúor tópico.
    [00:01:02] [Paciente] Tá certo, doutor. Posso continuar usando minha pasta de dente normal?
    [00:01:08] [Doutor] Pode sim, mas evita escovar com força. Eu vou te mandar um sensitive pra usar nessa região por 30 dias.
    [00:01:18] [Paciente] Obrigado, doutor. Até semana que vem.
  TEXT

  FAKE_SEGMENTS = [
    { start: 2,  end: 7,   speaker: 'Doutor',   text: 'Bom dia, João, tudo bem? Conta pra mim o que tá te incomodando.' },
    { start: 8,  end: 17,  speaker: 'Paciente', text: 'Bom dia, doutor. Faz umas duas semanas que tá doendo um dente do fundo do lado direito, principalmente quando bebo água gelada.' },
    { start: 18, end: 23,  speaker: 'Doutor',   text: 'Entendi. A dor é constante ou só quando você bebe algo frio?' },
    { start: 24, end: 29,  speaker: 'Paciente', text: 'É só com o frio mesmo. Quente não dói nada.' },
    { start: 30, end: 35,  speaker: 'Doutor',   text: 'Você tem alguma alergia a medicamento? Toma algum remédio atualmente?' },
    { start: 36, end: 44,  speaker: 'Paciente', text: 'Tenho alergia a penicilina, doutor. E só tomo remédio pra pressão, o losartana.' },
    { start: 45, end: 61,  speaker: 'Doutor',   text: 'Perfeito. Pelo que você relata, é compatível com hipersensibilidade dentinária no 47 ou 46. Eu vou te receitar um dessensibilizante pra usar agora, e quero te ver presencialmente em 15 dias pra aplicar flúor tópico.' },
    { start: 62, end: 67,  speaker: 'Paciente', text: 'Tá certo, doutor. Posso continuar usando minha pasta de dente normal?' },
    { start: 68, end: 77,  speaker: 'Doutor',   text: 'Pode sim, mas evita escovar com força. Eu vou te mandar um sensitive pra usar nessa região por 30 dias.' },
    { start: 78, end: 82,  speaker: 'Paciente', text: 'Obrigado, doutor. Até semana que vem.' }
  ].freeze

  FAKE_SOAP = {
    'subjetivo' => 'Paciente refere dor em dente inferior direito posterior há cerca de 2 semanas, desencadeada exclusivamente por estímulo frio (líquidos gelados). Sem dor espontânea ou ao calor.',
    'objetivo'  => 'Sem inspeção clínica completa (atendimento por teleconsulta). Paciente sem queixa estética. Histórico relevante: alergia a penicilina, em uso contínuo de losartana.',
    'avaliacao' => 'Hipótese diagnóstica: hipersensibilidade dentinária em dente 46 ou 47. Excluir cárie ativa e fratura coronária na avaliação presencial.',
    'plano'     => 'Indicado uso de dentifrício dessensibilizante (sensitive) duas vezes ao dia por 30 dias na região afetada. Orientação para evitar escovação com pressão excessiva. Agendar retorno presencial em 15 dias para aplicação de flúor tópico e exame clínico/radiográfico completo.'
  }.freeze

  FAKE_ATTENTION = [
    { 'type' => 'allergy',   'severity' => 'high',   'text' => 'Alergia a penicilina — evitar antibióticos beta-lactâmicos se houver indicação posterior.' },
    { 'type' => 'medication','severity' => 'medium', 'text' => 'Em uso de losartana (anti-hipertensivo) — atenção a interações em anestésicos com vasoconstritor adrenalina.' }
  ].freeze

  desc 'Setup dev completo (account + admin + paciente + agendamento) pra testar Sprint L'
  task setup_dev: :environment do
    puts '=== Setup dev Sprint L ==='

    account = Account.first || Account.create!(name: 'Klivy Dev')
    puts "  → Account ##{account.id} (#{account.name})"

    user = User.find_or_initialize_by(email: 'admin@klivy.local')
    user.assign_attributes(name: 'Dr. Admin', password: 'Klivy12345!', password_confirmation: 'Klivy12345!')
    user.skip_confirmation! if user.respond_to?(:skip_confirmation!) && !user.confirmed?
    user.save!

    AccountUser.find_or_create_by!(account: account, user: user) { |au| au.role = 'administrator' }
    puts "  → User #{user.email} (senha: Klivy12345!)"

    contact = Contact.find_or_create_by!(account: account, email: 'joao.silva@example.com') do |c|
      c.name        = 'João Silva'
      c.phone_number = '+5511999990000'
    end
    puts "  → Contact ##{contact.id} (#{contact.name})"

    # Tenta achar/criar Patient pro contact — necessário pra approve! gerar
    # ClinicalNote (que tem belongs_to :patient).
    if defined?(Patient)
      Patient.find_or_create_by!(account: account, contact: contact) do |p|
        p.name = contact.name
      end
      puts "  → Patient criado pra contact"
    end

    # Agendamento de teleconsulta no passado (status=completed pra simular
    # uma consulta encerrada que vai receber a gravação fake).
    event = AgendaEvent.where(account: account, contact: contact)
                       .where('starts_at > ?', 7.days.ago)
                       .first
    event ||= AgendaEvent.create!(
      account:    account,
      user:       user,
      contact:    contact,
      title:      'Consulta João Silva — teleconsulta',
      starts_at:  2.hours.ago,
      ends_at:    1.hour.ago,
      status:     'completed',
      event_type: 'consultation',
      custom_attributes: { 'telemedicine_enabled' => true }
    )
    puts "  → AgendaEvent ##{event.id} (#{event.title}) status=#{event.status}"

    setting = PatientPortalSetting.find_or_create_by!(account: account) do |s|
      s.active_preset = 'autonomy_guided'
    end
    setting.update!(telemedicine_recording: {
      'enabled'                   => true,
      'patient_consent_required'  => false, # facilita teste local
      'max_active_recordings'     => 15,
      'ai_evolution_enabled'      => true,
      'ai_provider'               => 'claude-sonnet-4.6'
    })
    puts "  → PatientPortalSetting (gravação habilitada, consent dispensado em dev)"

    puts ''
    puts '✅ Pronto. Próximos passos:'
    puts ''
    puts "  1. Login:    http://localhost:3000/app/login"
    puts "               email: admin@klivy.local"
    puts "               senha: Klivy12345!"
    puts ''
    puts "  2. Simular: bin/rails 'telemed:simulate[#{event.id}]'"
    puts ''
    puts "  3. Aba Teleconsulta: http://localhost:3000/app/accounts/#{account.id}/teleconsultas"
  end

  desc 'Lista AgendaEvents da conta pra escolher um pro simulate'
  task :list_events, [:account_id] => :environment do |_, args|
    account_id = args[:account_id] || Account.first&.id
    abort 'Nenhuma account encontrada — crie uma primeiro.' unless account_id

    events = AgendaEvent.where(account_id: account_id).order(starts_at: :desc).limit(15)
    if events.empty?
      puts "Conta #{account_id} não tem AgendaEvents. Crie um na agenda primeiro."
      next
    end

    puts "AgendaEvents recentes da conta #{account_id}:"
    puts "%-6s %-30s %-20s %-15s %-30s" % %w[ID Título Quando Status Paciente]
    puts "-" * 110
    events.each do |e|
      puts "%-6d %-30s %-20s %-15s %-30s" % [
        e.id,
        e.title.to_s.first(28),
        e.starts_at&.strftime('%Y-%m-%d %H:%M'),
        e.status,
        e.contact&.name.to_s.first(28)
      ]
    end
  end

  desc 'Habilita gravação de teleconsulta na conta (config patient_portal_setting)'
  task :enable_recording, [:account_id] => :environment do |_, args|
    account_id = args[:account_id] || Account.first&.id
    abort 'Nenhuma account encontrada.' unless account_id

    setting = PatientPortalSetting.find_or_create_by!(account_id: account_id) do |s|
      s.active_preset = 'autonomy_guided'
    end

    setting.update!(telemedicine_recording: {
      'enabled'                   => true,
      'patient_consent_required'  => true,
      'max_active_recordings'     => 15,
      'ai_evolution_enabled'      => true,
      'ai_provider'               => 'claude-sonnet-4.6'
    })

    puts "✅ Gravação habilitada na conta #{account_id}."
    puts "   Config: #{setting.reload.telemedicine_recording.inspect}"
  end

  desc 'Simula uma teleconsulta COMPLETA (fake transcript + evolução) pra testar UI'
  task :simulate, [:event_id] => :environment do |_, args|
    event_id = args[:event_id]
    abort 'Uso: bin/rails "telemed:simulate[EVENT_ID]"' unless event_id

    event = AgendaEvent.find_by(id: event_id)
    abort "AgendaEvent #{event_id} não encontrado." unless event

    puts "Simulando teleconsulta concluída em event=#{event.id} (#{event.title})"

    # 1. TelemedRecording fake — status=ready, sem keys de R2.
    rec = TelemedRecording.create!(
      agenda_event:        event,
      account:             event.account,
      recording_kind:      'audio',
      status:              'ready',
      composite_egress_id: "FAKE_EG_#{SecureRandom.hex(6)}",
      composite_audio_key: nil, # sem R2 — UI mostra "áudio indisponível"
      duration_seconds:    85,
      transcript_text:     FAKE_TRANSCRIPT,
      transcript_segments: FAKE_SEGMENTS.map(&:stringify_keys),
      transcript_provider: 'fake'
    )
    puts "  → TelemedRecording ##{rec.id} criado (status=ready)"

    # 2. ProposedEvolution fake — pronta pra revisar/aprovar.
    evo = ProposedEvolution.create!(
      telemed_recording: rec,
      provider:          'fake/simulate',
      soap_structure:    FAKE_SOAP,
      raw_markdown:      build_markdown(FAKE_SOAP, FAKE_ATTENTION),
      attention_points:  FAKE_ATTENTION,
      status:            'pending_review',
      input_tokens:      1234,
      output_tokens:     321
    )
    puts "  → ProposedEvolution ##{evo.id} criada (status=pending_review)"

    puts ""
    puts "📋 Tudo pronto. Abra no browser:"
    puts "   Lista:   http://localhost:3000/app/accounts/#{event.account_id}/teleconsultas"
    puts "   Detalhe: http://localhost:3000/app/accounts/#{event.account_id}/teleconsultas/#{event.id}"
    puts ""
    puts "💡 Você pode editar o SOAP, clicar 'Aprovar e publicar' → cria ClinicalNote draft."
  end

  desc 'Pipeline REAL: faz upload de áudio local → Whisper → Claude → ProposedEvolution'
  task :transcribe_real, [:event_id, :audio_path] => :environment do |_, args|
    event_id   = args[:event_id]
    audio_path = args[:audio_path]
    abort 'Uso: bin/rails "telemed:transcribe_real[EVENT_ID, /caminho/audio.ogg]"' if event_id.blank? || audio_path.blank?

    event = AgendaEvent.find_by(id: event_id)
    abort "AgendaEvent #{event_id} não encontrado." unless event

    abort "Arquivo de áudio não existe: #{audio_path}" unless File.exist?(audio_path)
    size_mb = (File.size(audio_path) / 1_048_576.0).round(2)
    puts "📁 Arquivo: #{audio_path} (#{size_mb} MB)"

    # 1. Cria TelemedRecording status=uploaded (pula etapa de Egress).
    storage_key = "accounts/#{event.account_id}/telemed/#{event.id}/manual/#{SecureRandom.hex(6)}-composite#{File.extname(audio_path)}"

    puts "⬆️  Upload pro R2: #{storage_key}"
    Telemed::RecordingStorage.upload(storage_key, audio_path)
    puts "✅ Upload completo"

    rec = TelemedRecording.create!(
      agenda_event:        event,
      account:             event.account,
      recording_kind:      'audio',
      status:              'uploaded',
      composite_egress_id: "MANUAL_#{SecureRandom.hex(6)}",
      composite_audio_key: storage_key,
      duration_seconds:    nil
    )
    puts "✅ TelemedRecording ##{rec.id} criado"

    # 2. Dispara TranscribeRecordingJob (modo composite-only).
    puts ''
    puts '🔄 Rodando TranscribeRecordingJob (Whisper)... aguarda 30s-2min'
    Telemed::TranscribeRecordingJob.new.perform(rec.id)

    rec.reload
    if rec.failed?
      puts "❌ Transcrição falhou: #{rec.failure_reason}"
      next
    end

    puts "✅ Transcrição pronta (#{rec.transcript_text.to_s.length} chars)"
    puts ''
    puts '─── PREVIEW DA TRANSCRIÇÃO ───'
    puts rec.transcript_text.to_s.first(800)
    puts '───────────────────────────────'

    # 3. GenerateEvolutionJob roda automaticamente após transcribe.
    # Espera ele terminar (vai rodar Claude).
    puts ''
    puts '🤖 Aguardando GenerateEvolutionJob (Claude)...'

    # Drain Sidekiq sync pra debugging — em prod o worker pega.
    # Como o transcribe acima rodou inline, o evolution_job foi perform_later
    # — precisa rodar inline também ou checar via worker async.
    puts '   (rode `bin/rails runner "Sidekiq::Queue.new.size"` se quiser ver fila)'
    puts ''
    puts "📋 Quando o job terminar, abra:"
    puts "   http://localhost:3000/app/accounts/#{event.account_id}/teleconsultas/#{event.id}"
  end

  desc 'Limpa TODAS as gravações + propostas da conta (reset pra testes)'
  task :reset, [:account_id] => :environment do |_, args|
    account_id = args[:account_id] || Account.first&.id
    abort 'Nenhuma account encontrada.' unless account_id

    rec_count = TelemedRecording.where(account_id: account_id).count
    evo_count = ProposedEvolution.joins(:telemed_recording)
                                 .where(telemed_recordings: { account_id: account_id })
                                 .count
    note_count = ClinicalNote.where(account_id: account_id, source: 'telemed_ai').count

    print "Deletar #{rec_count} gravações + #{evo_count} propostas + #{note_count} notas IA? [y/N] "
    answer = $stdin.gets.to_s.strip.downcase
    next unless answer == 'y'

    ClinicalNote.where(account_id: account_id, source: 'telemed_ai').delete_all
    ProposedEvolution.joins(:telemed_recording)
                     .where(telemed_recordings: { account_id: account_id }).delete_all
    TelemedRecording.where(account_id: account_id).delete_all

    puts "✅ Reset completo."
  end

  def build_markdown(soap, attention)
    <<~MD
      ## S — Subjetivo
      #{soap['subjetivo']}

      ## O — Objetivo
      #{soap['objetivo']}

      ## A — Avaliação
      #{soap['avaliacao']}

      ## P — Plano
      #{soap['plano']}

      ## Pontos de Atenção (JSON)
      ```json
      #{JSON.pretty_generate(attention)}
      ```
    MD
  end
end
