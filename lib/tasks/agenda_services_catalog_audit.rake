# PR-A da limpeza do catálogo (auditoria agendamento público §11):
# levantamento dos `agenda_services` de uma conta com classificação heurística
# para a clínica revisar e decidir o que arquivar.
#
# Contexto:
# Importação Clinicorp em `plugins/migration/app/services/migration/
# clinicorp_agenda_importer.rb` (PR-B vai corrigir) mapeava cada valor único
# da coluna `Procedures` do XLSX como `AgendaService` separado. `Procedures`
# é texto livre que a secretária Clinicorp digita ("dor urgencia", "caiu o
# bracket", "CPF: 093.858.129-55 - restauração", etc.), inflando o catálogo
# com anotações. Conta 31 (Mamedes) tem 2.048 serviços `kept`, 30-50 reais.
#
# Esta task NÃO toca o banco. Apenas:
#   - Lê os `agenda_services` da conta (todos, inclusive soft-deletados, para
#     dar visão completa pro CSV).
#   - Conta eventos vinculados (`kept` + `discarded`).
#   - Classifica heuristicamente em categorias para a clínica revisar.
#   - Exporta CSV em UTF-8 com BOM (Excel lê acentos direito) e separador `;`
#     (padrão Excel BR).
#
# Próximos passos:
#   1) Esta task gera o CSV.
#   2) Clínica revisa em Excel, adiciona coluna `acao` com valores:
#        manter            → não tocar
#        arquivar          → soft-delete; eventos perdem agenda_service_id
#        mover_para_desc   → soft-delete + concatena nome em description
#                            dos eventos que apontam pra ele (anotação)
#   3) PR-C (`agenda_services:catalog_cleanup`) consome o CSV revisado e
#      aplica.
#
# Uso:
#
#   bundle exec rails agenda_services:catalog_audit\[31\] > /tmp/svc_31.csv
#
# (Bash precisa de escape em `[` e `]` — zsh aceita sem escape se houver
# `unsetopt NOMATCH`. Em docker exec, alternativa: usar variável de ambiente.)
#
# Idempotente — só leitura.

namespace :agenda_services do
  desc 'Audita catálogo de agenda_services para uma conta (CSV em STDOUT, dry-run)'
  task :catalog_audit, [:account_id] => :environment do |_, args|
    account_id = args[:account_id].to_i
    if account_id.zero?
      warn 'Uso: rake agenda_services:catalog_audit[<account_id>]'
      exit 1
    end

    account = Account.find_by(id: account_id)
    if account.nil?
      warn "Conta #{account_id} não encontrada."
      exit 1
    end

    # Contagem de eventos por service_id, numa única query agrupada por service.
    # `kept` e `total` separados — clínica pode querer arquivar serviços com
    # eventos só `discarded` (lixo histórico) sem impactar o que aparece hoje.
    events_count_kept = AgendaEvent.kept
                                   .where(account_id: account_id)
                                   .where.not(agenda_service_id: nil)
                                   .group(:agenda_service_id)
                                   .count
    events_count_all  = AgendaEvent.where(account_id: account_id)
                                   .where.not(agenda_service_id: nil)
                                   .group(:agenda_service_id)
                                   .count
    last_event_at_map = AgendaEvent.kept
                                   .where(account_id: account_id)
                                   .where.not(agenda_service_id: nil)
                                   .group(:agenda_service_id)
                                   .maximum(:starts_at)

    # Proteção crítica (pergunta do usuário 2026-05-15): serviços vinculados a
    # TreatmentItem (procedimentos de plano de tratamento) representam o
    # catálogo CLÍNICO que a clínica de fato presta — mesmo que o nome bata
    # nas heurísticas de "anotação", se houver vínculo com plano de tratamento
    # ele é serviço real. Marca como `force_keep` na ação sugerida.
    treatment_items_count = TreatmentItem.where(account_id: account_id)
                                         .where.not(agenda_service_id: nil)
                                         .group(:agenda_service_id)
                                         .count

    services = AgendaService.where(account_id: account_id).order(:id).to_a

    # CSV via STDOUT. UTF-8 BOM + sep=; para Excel BR abrir acentuação correta.
    require 'csv'
    $stdout.write("\xEF\xBB\xBF") # BOM
    csv = CSV.new($stdout, col_sep: ';', force_quotes: true)

    csv << %w[
      id name name_length external_id created_at deleted_at
      events_kept events_all treatment_items last_event_at
      category_guess acao_sugerida
    ]

    counters = Hash.new(0)

    services.each do |svc|
      kept_count  = events_count_kept[svc.id].to_i
      total_count = events_count_all[svc.id].to_i
      ti_count    = treatment_items_count[svc.id].to_i
      last_at     = last_event_at_map[svc.id]
      guess       = classify(svc.name, total_count)
      # Vínculo com TreatmentItem força "manter" — sobrescreve heurística
      # textual. Clínica usou esse serviço em plano de tratamento, então é
      # catálogo clínico real, não anotação importada.
      action      = ti_count.positive? ? 'manter (clinico)' : suggested_action(guess, total_count)
      counters[ti_count.positive? ? 'manter_clinico' : guess] += 1

      csv << [
        svc.id,
        svc.name,
        svc.name.to_s.length,
        svc.external_id,
        svc.created_at&.iso8601,
        svc.deleted_at&.iso8601,
        kept_count,
        total_count,
        ti_count,
        last_at&.iso8601,
        guess,
        action
      ]
    end

    # Sumário para STDERR — não polui o CSV de STDOUT.
    warn ''
    warn "=== Resumo da auditoria — account_id=#{account_id} (#{account.name}) ==="
    warn "Total de agenda_services analisados: #{services.size}"
    warn ''
    counters.sort_by { |_, n| -n }.each do |cat, n|
      warn format('  %-25s %5d  (%s)', cat, n, action_summary(cat))
    end
    warn ''
    warn 'Próximo passo: abrir CSV no Excel, revisar coluna `acao_sugerida`,'
    warn 'preencher coluna `acao` (manter / arquivar / mover_para_desc) e'
    warn 'rodar `rake agenda_services:catalog_cleanup` (PR-C) com o CSV revisado.'
  end

  # ── heurísticas ───────────────────────────────────────────────────────────
  # Conservadoras de propósito: na dúvida, classifica como `revisar_manual`
  # para forçar olho humano em vez de auto-arquivar serviço real por engano.

  # Tenta detectar nome de serviço "real" vs anotação textual vs PII.
  # Não é decisão final — só sugestão. Clínica tem voto final no CSV.
  def classify(name, events_total)
    n = name.to_s.strip

    return 'orfao'           if events_total.zero?
    return 'pii_cpf'         if n.match?(/\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/)
    return 'pii_telefone'    if n.match?(/\(\d{2}\)\s*\d{4,5}-?\d{4}/)
    return 'pii_valor'       if n.match?(/R\$\s*\d/) || n.match?(/\d+[.,]\d{2}\b/)
    return 'anotacao_longa'  if n.length > 40
    return 'anotacao'        if n.include?(' / ') || n.count(',') >= 2
    return 'anotacao'        if n.match?(/\A(caiu|dor|quebr|incomod|sangr|av\b|rest\b|exo\b|esta com|nao sabe|sem custos)/i)

    'provavel_real'
  end

  def suggested_action(guess, events_total)
    case guess
    when 'orfao'           then 'arquivar'            # zero eventos, lixo puro
    when 'pii_cpf', 'pii_telefone'
                                events_total.positive? ? 'mover_para_desc' : 'arquivar'
    when 'pii_valor'       then events_total.positive? ? 'mover_para_desc' : 'arquivar'
    when 'anotacao_longa', 'anotacao'
                                events_total.positive? ? 'mover_para_desc' : 'arquivar'
    when 'provavel_real'   then 'manter'
    else 'revisar_manual'
    end
  end

  def action_summary(cat)
    case cat
    when 'manter_clinico'  then 'vinculado a plano de tratamento — manter sempre'
    when 'orfao'           then 'sem eventos vinculados — seguro arquivar'
    when 'pii_cpf'         then 'contém CPF — LGPD, mover para description ou arquivar'
    when 'pii_telefone'    then 'contém telefone — LGPD, mover para description'
    when 'pii_valor'       then 'contém valor monetário — anotação, não serviço'
    when 'anotacao_longa'  then 'nome > 40 chars — provável anotação'
    when 'anotacao'        then 'padrão de anotação — não é serviço'
    when 'provavel_real'   then 'manter (revisar manualmente se desconfiar)'
    else 'revisar manualmente'
    end
  end
end
