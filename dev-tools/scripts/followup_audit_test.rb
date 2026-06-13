# Bateria de testes de cenário do motor de follow-up (pós-auditoria).
# Roda tudo numa transação com ROLLBACK — não suja a base.
#   bundle exec rails runner dev-tools/scripts/followup_audit_test.rb
$pass = 0
$fail = 0
def check(name, cond)
  if cond
    $pass += 1
    puts "  ✅ #{name}"
  else
    $fail += 1
    puts "  ❌ FALHOU: #{name}"
  end
rescue StandardError => e
  $fail += 1
  puts "  💥 ERRO em #{name}: #{e.class}: #{e.message[0, 160]}"
end

ACC = Account.first
INBOX = ACC.inboxes.first
NS = "AUDIT_#{rand(100_000)}"

def mk_contact(n) = ACC.contacts.create!(name: "#{NS}-#{n}")
def mk_patient(c) = Patient.create!(account: ACC, contact: c, name: c.name)
def mk_service(n) = AgendaService.create!(account: ACC, name: "#{NS}-#{n}", duration_minutes: 30)

def mk_session(patient, service, performed_at, status: 'signed')
  tp = TreatmentPlan.create!(account: ACC, patient: patient, title: 'P')
  ti = TreatmentItem.create!(account: ACC, treatment_plan: tp, agenda_service_id: service.id, procedure_name: 'Procedimento')
  SessionLog.create!(account: ACC, patient: patient, treatment_item: ti, performed_at: performed_at, status: status)
end

def mk_event(service:, status:, starts_at:, contact_id: nil, custom: {}, deleted_at: nil)
  AgendaEvent.create!(account_id: ACC.id, contact_id: contact_id, agenda_service_id: service.id,
                      status: status, title: 'C', starts_at: starts_at, ends_at: starts_at + 30.minutes,
                      custom_attributes: custom, deleted_at: deleted_at)
end

def mk_conv(contact)
  # source_id de inbox WhatsApp precisa ser só dígitos (telefone).
  ci = ContactInbox.create!(contact: contact, inbox: INBOX, source_id: "5511#{rand(900_000_000) + 100_000_000}")
  Conversation.create!(account: ACC, inbox: INBOX, contact: contact, contact_inbox: ci, status: 'open')
end

def mk_msg(conv, type, content, created_at)
  m = conv.messages.create!(account_id: ACC.id, inbox_id: INBOX.id, message_type: type, content: content, private: false)
  m.update_columns(created_at: created_at, updated_at: created_at)
  m
end

def base_rule(attrs = {})
  AiAgent::FollowUpRule.new({
    account: ACC, name: "#{NS}-rule", trigger_type: 'no_response', action_type: 'generative',
    context_brief: 'oi', offset_hours: 3, offset_unit: 'hours'
  }.merge(attrs))
end

# Executa o bloco num SAVEPOINT (requires_new) — um RecordNotUnique do
# INSERT rola de volta só o savepoint, sem abortar a transação externa.
def raises_unique?
  ApplicationRecord.transaction(requires_new: true) { yield }
  false
rescue ActiveRecord::RecordNotUnique
  true
end

def succeeds_in_savepoint?
  ApplicationRecord.transaction(requires_new: true) { yield }
  true
rescue ActiveRecord::RecordNotUnique
  false
end

ApplicationRecord.transaction do
  puts "\n── A. VALIDAÇÕES ──"
  svc = mk_service('svc')
  other_acc = Account.where.not(id: ACC.id).first
  check('service_recall sem serviço → inválido',
        !base_rule(trigger_type: 'service_recall', recall_interval_value: 6).valid?)
  check('service_recall com serviço da conta → válido',
        base_rule(trigger_type: 'service_recall', agenda_service_id: svc.id, recall_interval_value: 6).valid?)
  if other_acc
    foreign = AgendaService.create!(account: other_acc, name: "#{NS}-foreign", duration_minutes: 30)
    r = base_rule(trigger_type: 'service_recall', agenda_service_id: foreign.id, recall_interval_value: 6)
    check('service_recall com serviço de OUTRA conta → inválido (ownership)', !r.valid? && r.errors[:agenda_service_id].any?)
  end
  check('generativo sem context_brief → inválido', !base_rule(context_brief: '').valid?)
  check('estático sem static_body → inválido', !base_rule(action_type: 'static', static_body: '', context_brief: '').valid?)
  check('persona_override > 2000 → inválido', !base_rule(persona_override: 'a' * 2001).valid?)

  # cadência com offsets colidindo
  r_collide = base_rule
  r_collide.steps.build(position: 1, offset_hours: 3, offset_unit: 'hours', context_brief: 'p2') # = base 3h
  check('cadência: passo com MESMO offset do base → inválido (anti-colisão)', !r_collide.valid?)
  r_ok = base_rule
  r_ok.steps.build(position: 1, offset_hours: 6, offset_unit: 'hours', context_brief: 'p2')
  check('cadência: offsets distintos → válido', r_ok.valid?)

  puts "\n── B. IDEMPOTÊNCIA (índice COALESCE + step_id) ──"
  c = mk_contact('idem')
  rule = base_rule.tap(&:save!)
  e1 = AiAgent::FollowUpExecution.create!(account: ACC, rule: rule, contact_id: c.id, agenda_event_id: nil, step_id: nil, target_at: Time.current, status: 'pending')
  dup_blocked = raises_unique? do
    AiAgent::FollowUpExecution.create!(account: ACC, rule: rule, contact_id: c.id, agenda_event_id: nil, step_id: nil, target_at: e1.target_at, status: 'pending')
  end
  check('no_response (agenda_event_id NULL): duplicata MESMO target_at bloqueada pelo índice COALESCE', dup_blocked)
  s = AiAgent::FollowUpStep.create!(rule: rule, position: 1, offset_hours: 6, offset_unit: 'hours', context_brief: 'p2')
  ok_diff_step = succeeds_in_savepoint? do
    AiAgent::FollowUpExecution.create!(account: ACC, rule: rule, contact_id: c.id, agenda_event_id: nil, step_id: s.id, target_at: e1.target_at, status: 'pending')
  end
  check('mesmo target_at mas STEP diferente → execução distinta (não colide)', ok_diff_step)

  puts "\n── C. find_no_response (paciente em silêncio após fala da clínica) ──"
  rule_nr = base_rule(offset_hours: 2, offset_unit: 'hours').tap(&:save!)
  # 1) clínica falou há 5h e o paciente nunca respondeu → candidato
  c1 = mk_contact('nr1')
  conv1 = mk_conv(c1)
  anchor_c1 = mk_msg(conv1, :outgoing, 'oi, conseguimos confirmar?', 5.hours.ago)
  # 2) clínica falou MAS o paciente respondeu depois → NÃO candidato
  c2 = mk_contact('nr2')
  conv2 = mk_conv(c2)
  mk_msg(conv2, :outgoing, 'oi!', 5.hours.ago)
  mk_msg(conv2, :incoming, 'tudo certo!', 4.hours.ago)
  # 3) fala da clínica RECENTE (< offset) → ainda NÃO
  c3 = mk_contact('nr3')
  conv3 = mk_conv(c3)
  mk_msg(conv3, :outgoing, 'acabei de mandar', 5.minutes.ago)
  # 4) PACIENTE falou por último (clínica devendo resposta) → NUNCA cutuca
  c4 = mk_contact('nr4')
  conv4 = mk_conv(c4)
  mk_msg(conv4, :incoming, 'alô? alguém me responde?', 5.hours.ago)
  # Força status 'open' (0) — a inbox WhatsApp tem AgentBot que pode jogar
  # a conversa pra 'pending' ao receber mensagem; update_columns ignora callback.
  [conv1, conv2, conv3, conv4].each { |cv| cv.update_columns(status: 0) }
  res_nr = AiAgent::FollowUps::CandidateFinder.new(rule_nr).call
  ids = res_nr.map { |x| x[:contact_id] }
  check('clínica falou e paciente silente ≥ offset → candidato', ids.include?(c1.id))
  check('paciente respondeu depois → NÃO candidato', !ids.include?(c2.id))
  check('fala da clínica recente (< offset) → ainda NÃO candidato', !ids.include?(c3.id))
  check('paciente esperando resposta da clínica → NUNCA cutuca', !ids.include?(c4.id))
  cand_c1 = res_nr.find { |x| x[:contact_id] == c1.id }
  check('âncora do episódio = a fala da clínica (target = âncora+offset)',
        cand_c1 && cand_c1[:target_at] == anchor_c1.created_at + 2.hours)

  puts "\n── D. OutboundMessage / template ──"
  conv_d = mk_conv(mk_contact('out'))
  rule_static = base_rule(action_type: 'static', static_body: 'Oi {{nome}}!', context_brief: '').tap { |r| r.save!(validate: false) }
  # dentro da janela (mock) — texto estático
  Mock = Struct.new(:reply) { def can_reply?; reply; end; def inbox; nil; end }
  om = AiAgent::FollowUps::OutboundMessage.new(rule: rule_static, contact: conv_d.contact)
  r_in = om.call(Mock.new(true))
  check('estático dentro da janela → texto livre renderizado', r_in.content.to_s.include?(conv_d.contact.name.to_s) || r_in.content.present?)
  # fora da janela sem template → skip
  r_out = AiAgent::FollowUps::OutboundMessage.new(rule: rule_static, contact: conv_d.contact).call(Mock.new(false))
  check('fora da janela sem template → skip outside_messaging_window', r_out.skip_reason == 'outside_messaging_window')
  # body_params nunca em branco (var vazia → "-")
  rule_tpl = base_rule(cloud_template_name: 't', cloud_template_lang: 'pt_BR', cloud_template_params: %w[nome data]).tap { |r| r.save!(validate: false) }
  omt = AiAgent::FollowUps::OutboundMessage.new(rule: rule_tpl, contact: mk_contact('tpl'))
  body = omt.send(:body_params) # data vazia (sem agenda) → '-'
  check('body_params: variável vazia vira "-" (não desloca posições)', body['2'] == '-' && body['1'].present?)

  puts "\n── E. eco-detection (falso-positivo) ──"
  mg = AiAgent::FollowUps::MessageGenerator.new(rule: base_rule, contact: mk_contact('eco'))
  check('"Você é a próxima da fila!" → NÃO é descartada', mg.send(:output_looks_like_message?, 'Você é a próxima da fila, falta pouco! ❤️'))
  check('"Você é a Bea, recepcionista..." → descartada (eco)', !mg.send(:output_looks_like_message?, 'Você é a Bea, recepcionista virtual da clínica.'))

  puts "\n── F. ServiceRecallFinder ──"
  svc2 = mk_service('botox')
  ct = mk_contact('recall'); pt = mk_patient(ct)
  mk_session(pt, svc2, 6.months.ago, status: 'signed')
  rule_sr = base_rule(trigger_type: 'service_recall', agenda_service_id: svc2.id, recall_interval_value: 6, context_brief: 'renovar').tap(&:save!)
  step0 = rule_sr.dispatch_steps.first
  base_res = AiAgent::FollowUps::ServiceRecallFinder.new(rule_sr, step0).call
  check('reativação por serviço: candidato encontrado', base_res.size == 1 && base_res.first[:contact_id] == ct.id)
  # reagendou via contact_id → exclui
  ev1 = mk_event(service: svc2, status: 'confirmed', starts_at: 3.days.from_now, contact_id: ct.id)
  check('reagendou (contact_id) → excluído', AiAgent::FollowUps::ServiceRecallFinder.new(rule_sr, step0).call.empty?)
  ev1.destroy
  # reagendou via custom_attributes.patient_id (evento da UI com contact_id nil) → exclui (#11)
  ev2 = mk_event(service: svc2, status: 'scheduled', starts_at: 4.days.from_now, contact_id: nil, custom: { 'patient_id' => pt.id })
  check('reagendou (custom_attributes.patient_id, contact_id nil) → excluído (#11)', AiAgent::FollowUps::ServiceRecallFinder.new(rule_sr, step0).call.empty?)
  # soft-deleted não conta (#12)
  ev2.update_columns(deleted_at: Time.current)
  check('evento futuro SOFT-DELETED não suprime o recall (#12)', AiAgent::FollowUps::ServiceRecallFinder.new(rule_sr, step0).call.size == 1)
  # single-shot: mesmo com passo extra, só base (#20)
  rule_sr.steps.create!(position: 1, offset_hours: 6, offset_unit: 'hours', context_brief: 'extra')
  cf = AiAgent::FollowUps::CandidateFinder.new(rule_sr).call
  check('service_recall single-shot: 1 candidato mesmo com passo extra (#20)', cf.size == 1)
  # Unidade nova: intervalo em DIAS (ciclos curtos — limpeza quinzenal etc.)
  svc_d = mk_service('limpeza')
  ct_d = mk_contact('recall-dias')
  pt_d = mk_patient(ct_d)
  mk_session(pt_d, svc_d, 15.days.ago)
  rule_d = base_rule(trigger_type: 'service_recall', agenda_service_id: svc_d.id,
                     recall_interval_value: 15, recall_interval_unit: 'days', context_brief: 'voltar').tap(&:save!)
  res_d = AiAgent::FollowUps::ServiceRecallFinder.new(rule_d, rule_d.dispatch_steps.first).call
  check('recall em DIAS (15 dias após a sessão) → candidato encontrado',
        res_d.size == 1 && res_d.first[:contact_id] == ct_d.id)
  check('recall_interval_unit desconhecida → inválido',
        !base_rule(trigger_type: 'service_recall', agenda_service_id: svc_d.id,
                   recall_interval_value: 5, recall_interval_unit: 'decades').valid?)
  check('recall em days acima do teto (400) → inválido',
        !base_rule(trigger_type: 'service_recall', agenda_service_id: svc_d.id,
                   recall_interval_value: 400, recall_interval_unit: 'days').valid?)
  # Unidades curtas pra TESTE (minutos/horas) e anos
  svc_m2 = mk_service('teste-min')
  ct_m2 = mk_contact('recall-min')
  pt_m2 = mk_patient(ct_m2)
  mk_session(pt_m2, svc_m2, 5.minutes.ago)
  rule_m2 = base_rule(trigger_type: 'service_recall', agenda_service_id: svc_m2.id,
                      recall_interval_value: 2, recall_interval_unit: 'minutes', context_brief: 'volta').tap(&:save!)
  res_m2 = AiAgent::FollowUps::ServiceRecallFinder.new(rule_m2, rule_m2.dispatch_steps.first).call
  check('recall em MINUTOS (sessão 5min atrás, intervalo 2min) → candidato (pra testar sem esperar)',
        res_m2.size == 1 && res_m2.first[:contact_id] == ct_m2.id)
  check('recall_interval = 2 minutos → Duration correta', rule_m2.recall_interval == 2.minutes)
  check('recall em HORAS → válido',
        base_rule(trigger_type: 'service_recall', agenda_service_id: svc_m2.id,
                  recall_interval_value: 3, recall_interval_unit: 'hours').valid?)
  check('recall em ANOS → válido',
        base_rule(trigger_type: 'service_recall', agenda_service_id: svc_m2.id,
                  recall_interval_value: 1, recall_interval_unit: 'years').valid?)
  check('recall em ANOS acima do teto (11) → inválido',
        !base_rule(trigger_type: 'service_recall', agenda_service_id: svc_m2.id,
                   recall_interval_value: 11, recall_interval_unit: 'years').valid?)

  puts "\n── G. StopConditions (soft-delete) ──"
  c_stop = mk_contact('stop')
  rule_stop = base_rule(stop_on_booking: true).tap(&:save!)
  sc = AiAgent::FollowUps::StopConditions.new(rule_stop)
  cand = { contact_id: c_stop.id, agenda_event_id: nil, step_id: nil }
  evb = mk_event(service: svc, status: 'confirmed', starts_at: 2.days.from_now, contact_id: c_stop.id)
  check('stop_on_booking: agendamento futuro → para', sc.stopped?(cand))
  evb.update_columns(deleted_at: Time.current)
  check('stop_on_booking: agendamento SOFT-DELETED → NÃO para (#12)', !sc.stopped?(cand))

  puts "\n── H. appointment_confirmed wiring (#9) ──"
  rule_ac = base_rule(trigger_type: 'appointment_confirmed', context_brief: 'confirmado!').tap(&:save!)
  c_ac = mk_contact('ac')
  enq = 0
  callbacks_ok = AgendaEvent.instance_methods.include?(:dispatch_appointment_confirmed_follow_ups)
  check('AgendaEvent tem o callback dispatch_appointment_confirmed_follow_ups (#9)', callbacks_ok)
  # dispara o job manualmente e verifica que cria execução p/ a regra
  ev_ac = mk_event(service: svc, status: 'confirmed', starts_at: 1.day.from_now, contact_id: c_ac.id)
  AiAgent::FollowUps::DispatchAppointmentConfirmedJob.new.perform(ev_ac.id)
  check('DispatchAppointmentConfirmedJob cria execução p/ regra appointment_confirmed', AiAgent::FollowUpExecution.where(rule_id: rule_ac.id, agenda_event_id: ev_ac.id).exists?)

  puts "\n── I. Dispatcher: dedup intra-run entre regras (#17) ──"
  c_dup = mk_contact('dup'); pt_dup = mk_patient(c_dup)
  svc3 = mk_service('s3'); mk_session(pt_dup, svc3, 6.months.ago)
  svc4 = mk_service('s4'); mk_session(pt_dup, svc4, 6.months.ago)
  base_rule(trigger_type: 'service_recall', agenda_service_id: svc3.id, recall_interval_value: 6, context_brief: 'r3').save!
  base_rule(trigger_type: 'service_recall', agenda_service_id: svc4.id, recall_interval_value: 6, context_brief: 'r4').save!
  AiAgent::FollowUpDispatcherPerAccountJob.new.perform(ACC.id)
  enq_count = AiAgent::FollowUpExecution.where(account_id: ACC.id, contact_id: c_dup.id).where.not(status: 'skipped').count
  check('mesmo contato candidato em 2 regras no mesmo run → no máx 1 enviado (#17)', enq_count <= 1)

  puts "\n── J. Finders de agenda: contact_id nil + custom_attributes.patient_id ──"
  # Em dados reais (UI e Bea), AgendaEvent costuma ter contact_id NIL com o
  # paciente em custom_attributes.patient_id — o finder precisa resolver o
  # contato via Patient, senão pre/post/no_show nunca acham candidato.
  c_j = mk_contact('agenda-nil'); pt_j = mk_patient(c_j)
  rule_pre = base_rule(trigger_type: 'pre_appointment', offset_hours: 24, context_brief: 'lembrete').tap(&:save!)
  ev_j = mk_event(service: svc, status: 'confirmed', starts_at: 24.hours.from_now,
                  contact_id: nil, custom: { 'patient_id' => pt_j.id })
  cands_j = AiAgent::FollowUps::CandidateFinder.new(rule_pre).call
  check('pre_appointment: evento com contact_id NIL + patient_id → candidato (contato via Patient)',
        cands_j.any? { |c| c[:contact_id] == c_j.id && c[:agenda_event_id] == ev_j.id })
  # soft-deleted na janela → NÃO candidata
  ev_j.update_columns(deleted_at: Time.current)
  cands_j2 = AiAgent::FollowUps::CandidateFinder.new(rule_pre).call
  check('pre_appointment: evento SOFT-DELETED na janela → NÃO candidato',
        cands_j2.none? { |c| c[:agenda_event_id] == ev_j.id })

  puts "\n── K. DispatchAppointmentConfirmedJob: contact nil / soft-delete ──"
  rule_ac2 = base_rule(trigger_type: 'appointment_confirmed', context_brief: 'ok!').tap(&:save!)
  c_k = mk_contact('ac-nil'); pt_k = mk_patient(c_k)
  ev_k = mk_event(service: svc, status: 'confirmed', starts_at: 2.days.from_now,
                  contact_id: nil, custom: { 'patient_id' => pt_k.id })
  AiAgent::FollowUps::DispatchAppointmentConfirmedJob.new.perform(ev_k.id)
  check('appointment_confirmed: evento com contact_id NIL + patient_id → cria execução',
        AiAgent::FollowUpExecution.where(rule_id: rule_ac2.id, agenda_event_id: ev_k.id, contact_id: c_k.id).exists?)
  ev_k2 = mk_event(service: svc, status: 'confirmed', starts_at: 3.days.from_now,
                   contact_id: c_k.id, deleted_at: Time.current)
  AiAgent::FollowUps::DispatchAppointmentConfirmedJob.new.perform(ev_k2.id)
  check('appointment_confirmed: evento SOFT-DELETED → NÃO cria execução',
        !AiAgent::FollowUpExecution.where(rule_id: rule_ac2.id, agenda_event_id: ev_k2.id).exists?)

  puts "\n── L. Cadência no_response sobrevive ao próprio envio ──"
  # O outgoing que o MOTOR mandou (registrado em execution.message_id) não
  # re-ancora nem mata a cadência — a âncora segue sendo a última fala
  # REAL da clínica (humano/Bea conversacional).
  rule_l = base_rule(offset_hours: 1, offset_unit: 'hours', context_brief: 'b1').tap(&:save!)
  step_l2 = rule_l.steps.create!(position: 1, offset_hours: 6, offset_unit: 'hours', context_brief: 'b2')
  c_l = mk_contact('cad')
  conv_l = mk_conv(c_l)
  anchor = mk_msg(conv_l, :outgoing, 'oi, vamos remarcar?', 7.hours.ago) # clínica (âncora)
  bot_msg = mk_msg(conv_l, :outgoing, 'follow-up beat 1', 6.hours.ago)  # motor
  AiAgent::FollowUpExecution.create!(account: ACC, rule: rule_l, contact_id: c_l.id, conversation_id: conv_l.id,
                                     step_id: nil, target_at: anchor.created_at + 1.hour,
                                     status: 'sent', sent_at: 6.hours.ago, message_id: bot_msg.id)
  conv_l.update_columns(status: 0)
  cands_l = AiAgent::FollowUps::CandidateFinder.new(rule_l).call
  check('no_response: outgoing do PRÓPRIO motor não re-ancora → passo 2 vira candidato',
        cands_l.any? { |c| c[:contact_id] == c_l.id && c[:step_id] == step_l2.id })
  check('no_response: passo 1 já executado não re-candidata',
        cands_l.none? { |c| c[:contact_id] == c_l.id && c[:step_id].nil? })
  # outgoing humano NOVO re-ancora o episódio (espera offset de novo)
  c_l2 = mk_contact('cad2')
  conv_l2 = mk_conv(c_l2)
  mk_msg(conv_l2, :outgoing, 'oi', 7.hours.ago)
  mk_msg(conv_l2, :outgoing, 'resposta humana nova', 30.minutes.ago)
  conv_l2.update_columns(status: 0)
  check('no_response: outgoing humano novo re-ancora (silêncio < offset → ainda não)',
        AiAgent::FollowUps::CandidateFinder.new(rule_l).call.none? { |c| c[:contact_id] == c_l2.id })
  # conversa em PENDING (bot da Bea) também é elegível
  c_l3 = mk_contact('cad3')
  conv_l3 = mk_conv(c_l3)
  mk_msg(conv_l3, :outgoing, 'oi, posso ajudar em algo mais?', 7.hours.ago)
  conv_l3.update_columns(status: ::Conversation.statuses[:pending])
  check('no_response: conversa em status PENDING (bot) também é elegível',
        AiAgent::FollowUps::CandidateFinder.new(rule_l).call.any? { |c| c[:contact_id] == c_l3.id })

  puts "\n── M. Cap e stop_on_reply não bloqueiam episódios/eventos FUTUROS ──"
  # Cap: recall já enviado há 7 meses não pode bloquear o recall da sessão nova.
  svc_m = mk_service('botox-m')
  c_m = mk_contact('cap'); pt_m = mk_patient(c_m)
  rule_m = base_rule(trigger_type: 'service_recall', agenda_service_id: svc_m.id,
                     recall_interval_value: 6, context_brief: 'renove', max_per_target: 1).tap(&:save!)
  AiAgent::FollowUpExecution.create!(account: ACC, rule: rule_m, contact_id: c_m.id, step_id: nil,
                                     target_at: 7.months.ago, status: 'sent', sent_at: 7.months.ago)
  mk_session(pt_m, svc_m, 6.months.ago)
  cands_m = AiAgent::FollowUps::CandidateFinder.new(rule_m).call
  check('service_recall: recall antigo já enviado NÃO bloqueia o recall da sessão nova (cap por episódio)',
        cands_m.any? { |c| c[:contact_id] == c_m.id })
  # stop_on_reply: resposta dada após follow-up do evento E1 não barra o passo 1 do evento E2
  rule_sr2 = base_rule(trigger_type: 'post_appointment', stop_on_reply: true, context_brief: 'pós').tap(&:save!)
  c_m2 = mk_contact('reply'); conv_m2 = mk_conv(c_m2)
  ev_e1 = mk_event(service: svc, status: 'completed', starts_at: 60.days.ago, contact_id: c_m2.id)
  AiAgent::FollowUpExecution.create!(account: ACC, rule: rule_sr2, contact_id: c_m2.id, agenda_event_id: ev_e1.id,
                                     step_id: nil, target_at: 59.days.ago, status: 'sent', sent_at: 59.days.ago)
  mk_msg(conv_m2, :incoming, 'obrigado!', 58.days.ago) # respondeu ao follow-up de E1
  ev_e2 = mk_event(service: svc, status: 'completed', starts_at: 1.day.ago, contact_id: c_m2.id)
  sc_m = AiAgent::FollowUps::StopConditions.new(rule_sr2)
  cand_e2 = { contact_id: c_m2.id, agenda_event_id: ev_e2.id, step_id: nil, anchor_at: ev_e2.starts_at,
              target_at: ev_e2.starts_at + 3.hours }
  check('stop_on_reply: resposta antiga (evento E1) NÃO barra o passo 1 do evento novo E2',
        !sc_m.stopped?(cand_e2))
  # ... mas resposta após o envio DO PRÓPRIO E2 barra os beats seguintes
  AiAgent::FollowUpExecution.create!(account: ACC, rule: rule_sr2, contact_id: c_m2.id, agenda_event_id: ev_e2.id,
                                     step_id: nil, target_at: ev_e2.starts_at + 3.hours,
                                     status: 'sent', sent_at: 10.hours.ago)
  mk_msg(conv_m2, :incoming, 'tudo ótimo', 5.hours.ago)
  check('stop_on_reply: resposta após o envio do PRÓPRIO evento barra os próximos beats',
        sc_m.stopped?(cand_e2))

  puts "\n── N. stop_on_booking enxerga evento da UI (contact_id nil) ──"
  rule_n = base_rule(stop_on_booking: true, context_brief: 'volta?').tap(&:save!)
  c_n = mk_contact('book-ui'); pt_n = mk_patient(c_n)
  mk_event(service: svc, status: 'scheduled', starts_at: 5.days.from_now,
           contact_id: nil, custom: { 'patient_id' => pt_n.id })
  check('stop_on_booking: agendamento futuro criado pela UI (contact nil + patient_id) → para a cadência',
        AiAgent::FollowUps::StopConditions.new(rule_n).stopped?({ contact_id: c_n.id, agenda_event_id: nil, step_id: nil }))

  puts "\n── O. SendFollowUpJob resolve conversa RESOLVED (paciente dormente) ──"
  c_o = mk_contact('dormant')
  conv_o = mk_conv(c_o)
  conv_o.update_columns(status: ::Conversation.statuses[:resolved])
  exec_o = AiAgent::FollowUpExecution.new(account: ACC, contact_id: c_o.id, conversation_id: nil)
  resolved = AiAgent::SendFollowUpJob.new.send(:resolve_conversation, exec_o, c_o, ACC)
  check('reativação: contato só com conversa RESOLVED → usa a resolved (não pula por no_open_conversation)',
        resolved&.id == conv_o.id)

  puts "\n── P. Steps in-place: editar regra NÃO troca step_id ──"
  # O controller sincroniza os passos in-place (autosave) — recriar com
  # destroy_all trocaria os step_id e quebraria idempotência/cap/execuções
  # pendentes chaveadas neles.
  ctrl = AiAgent::Api::V1::Accounts::FollowUpRulesController.new
  rule_p = base_rule(context_brief: 'base').tap(&:save!)
  ctrl.send(:assign_steps, rule_p, [{ offset_hours: 6, offset_unit: 'hours', context_brief: 'p2' },
                                    { offset_hours: 24, offset_unit: 'hours', context_brief: 'p3' }])
  rule_p.save!
  rule_p.steps.reload
  ids_before = rule_p.steps.ordered.pluck(:id)
  ctrl.send(:assign_steps, rule_p, [{ offset_hours: 6, offset_unit: 'hours', context_brief: 'p2 EDITADO' },
                                    { offset_hours: 24, offset_unit: 'hours', context_brief: 'p3' }])
  rule_p.save!
  rule_p.steps.reload
  check('re-mandar a lista de steps no update → MESMOS step_id (sem destroy_all)',
        ids_before.size == 2 && rule_p.steps.ordered.pluck(:id) == ids_before)
  check('conteúdo editado do passo persistiu (autosave)',
        rule_p.steps.ordered.first.context_brief == 'p2 EDITADO')
  ctrl.send(:assign_steps, rule_p, [{ offset_hours: 6, offset_unit: 'hours', context_brief: 'p2 EDITADO' }])
  rule_p.save!
  rule_p.steps.reload
  check('lista menor → excedente destruído, id do primeiro preservado',
        rule_p.steps.ordered.pluck(:id) == [ids_before.first])
  check('status_filter com chave estranha → inválido', !base_rule(status_filter: { 'foo' => 'bar' }).valid?)
  check('status_filter {"allowed": ["no_show"]} → válido', base_rule(status_filter: { 'allowed' => ['no_show'] }).valid?)

  puts "\n── Q. Cooldown anti-spam configurável por regra ──"
  job = AiAgent::FollowUpDispatcherPerAccountJob.new
  c_cd = mk_contact('cooldown')
  rule_a = base_rule(context_brief: 'a').tap(&:save!)
  rule_b10 = base_rule(context_brief: 'b', cooldown_minutes: 10).tap(&:save!)
  rule_b0 = base_rule(context_brief: 'b0', cooldown_minutes: 0).tap(&:save!)
  # outra regra mandou follow-up há 5 min pra esse contato
  AiAgent::FollowUpExecution.create!(account: ACC, rule: rule_a, contact_id: c_cd.id, step_id: nil,
                                     target_at: 5.minutes.ago, status: 'sent', sent_at: 5.minutes.ago)
  check('cooldown=10: envio de OUTRA regra há 5min → bloqueia (recently_followed_up? true)',
        job.send(:recently_followed_up?, rule_b10, c_cd.id))
  check('cooldown=0: mesma situação → NÃO bloqueia (sem trava de tempo)',
        !job.send(:recently_followed_up?, rule_b0, c_cd.id))
  # envio antigo (há 20min) não bloqueia cooldown de 10
  c_cd2 = mk_contact('cooldown2')
  AiAgent::FollowUpExecution.create!(account: ACC, rule: rule_a, contact_id: c_cd2.id, step_id: nil,
                                     target_at: 20.minutes.ago, status: 'sent', sent_at: 20.minutes.ago)
  check('cooldown=10: envio há 20min (> janela) → NÃO bloqueia', !job.send(:recently_followed_up?, rule_b10, c_cd2.id))
  # beats da PRÓPRIA regra nunca contam pro cooldown
  c_cd3 = mk_contact('cooldown3')
  AiAgent::FollowUpExecution.create!(account: ACC, rule: rule_b10, contact_id: c_cd3.id, step_id: nil,
                                     target_at: 2.minutes.ago, status: 'sent', sent_at: 2.minutes.ago)
  check('cooldown: envio da PRÓPRIA regra não conta (cadência livre)', !job.send(:recently_followed_up?, rule_b10, c_cd3.id))
  check('cooldown_minutes negativo → inválido', !base_rule(cooldown_minutes: -1).valid?)
  check('cooldown_minutes acima do teto (10081) → inválido', !base_rule(cooldown_minutes: 10_081).valid?)
  check('cooldown_minutes 0 → válido', base_rule(cooldown_minutes: 0).valid?)

  puts "\n── RESUMO ──"
  puts "PASS=#{$pass} FAIL=#{$fail}"
  raise ActiveRecord::Rollback
end
puts $fail.zero? ? "\n🎉 TODOS OS CENÁRIOS PASSARAM (rolled back)" : "\n⚠️  #{$fail} cenário(s) falharam"
