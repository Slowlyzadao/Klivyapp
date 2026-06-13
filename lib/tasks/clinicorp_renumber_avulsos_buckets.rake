namespace :clinicorp do
  # Backfill 2026-05-12: renumera `Financial::Installment#number` dentro de cada
  # bucket "Avulsos" do importador Clinicorp para refletir a ordem cronológica
  # de `due_date`. Buckets criados pelo importer antes desta data herdaram a
  # ordem de export do CSV PaymentItem.xlsx (aleatória), o que fazia parcelas
  # aparecerem fora de ordem na timeline financeira do paciente. O fix do
  # importer (sort por DueDate antes de iterar) cobre novas importações;
  # esta rake corrige dados já importados.
  #
  # Escopo: somente buckets com metadata.kind = 'avulsos_bucket'. Budgets reais
  # do Klivy nativo já têm `number` alinhado com `due_date` pelo gerador de
  # parcelas — não são tocados.
  #
  # Estratégia anti-conflito com `idx_uniq_installment_number_per_budget`
  # (índice único parcial em (financial_budget_id, number) WHERE deleted_at IS NULL):
  # renumera em 2 passos por bucket dentro de uma transação:
  #   1) move todos pra faixa negativa (-(idx+1)) — libera slots 1..N
  #   2) atribui 1..N na ordem cronológica (due_date, clinicorp_item_id)
  # Negativos não colidem porque nenhum installment em produção tem number < 0.
  #
  # Uso:
  #   bundle exec rake clinicorp:renumber_avulsos_buckets
  #   bundle exec rake clinicorp:renumber_avulsos_buckets DRY_RUN=1
  desc 'Renumera installments dos buckets Avulsos Clinicorp por due_date (2026-05-12 backfill)'
  task renumber_avulsos_buckets: :environment do
    dry_run = ENV['DRY_RUN'].to_s == '1'

    buckets = Financial::Budget.where("metadata->>'kind' = 'avulsos_bucket'")
    total = buckets.count
    puts "Buckets Avulsos encontrados: #{total}#{dry_run ? ' (DRY_RUN)' : ''}"
    puts '─' * 70

    stats = { renumbered: 0, already_ordered: 0, empty: 0, errors: 0 }

    buckets.find_each.with_index(1) do |bucket, i|
      installments = bucket.installments.where(deleted_at: nil).to_a

      if installments.empty?
        stats[:empty] += 1
        next
      end

      sorted = installments.sort_by do |inst|
        # Date.new(9999,1,1) joga parcela sem due_date pro fim. Tiebreak pelo
        # clinicorp_item_id (string) — determinístico entre re-runs e estável
        # mesmo se a ordem de carga do find_each variar.
        [inst.due_date || Date.new(9999, 1, 1),
         inst.metadata&.dig('clinicorp_item_id').to_s]
      end

      already_ok = sorted.each_with_index.all? { |inst, idx| inst.number == idx + 1 }
      if already_ok
        stats[:already_ordered] += 1
        next
      end

      if dry_run
        before = installments.sort_by(&:number).map { |i| "#{i.number}=#{i.due_date}" }.join(' ')
        after  = sorted.each_with_index.map { |i, idx| "#{idx + 1}=#{i.due_date}" }.join(' ')
        puts "[#{i}/#{total}] bucket #{bucket.id} (account #{bucket.account_id}, patient #{bucket.patient_id}) — #{installments.size} parcelas"
        puts "  antes:  #{before}"
        puts "  depois: #{after}"
        stats[:renumbered] += 1
        next
      end

      begin
        ActiveRecord::Base.transaction do
          # Passo 1: faixa negativa
          sorted.each_with_index do |inst, idx|
            Financial::Installment.where(id: inst.id).update_all(number: -(idx + 1))
          end
          # Passo 2: 1..N na ordem cronológica
          sorted.each_with_index do |inst, idx|
            Financial::Installment.where(id: inst.id).update_all(number: idx + 1)
          end
        end
        stats[:renumbered] += 1
        puts "[#{i}/#{total}] OK bucket #{bucket.id} (#{installments.size} parcelas)"
      rescue StandardError => e
        stats[:errors] += 1
        puts "[#{i}/#{total}] ERRO bucket #{bucket.id} (account #{bucket.account_id}): #{e.class}: #{e.message}"
      end
    end

    puts '─' * 70
    puts "Renumerados: #{stats[:renumbered]}"
    puts "Já em ordem: #{stats[:already_ordered]}"
    puts "Vazios:      #{stats[:empty]}"
    puts "Erros:       #{stats[:errors]}"
  end
end
