# Varredura READ-ONLY: lista pacientes com e-mail ou telefone em formato
# inválido. NÃO altera nada — apenas gera a lista para correção manual.
#
# Por que manual? Não há como auto-corrigir: ninguém sabe qual o domínio certo
# de "fulano@gmail" nem os dígitos que faltam num telefone truncado. Apagar/
# zerar seria destrutivo e perderia informação parcial. Então a saída é uma
# lista pra equipe revisar (a validação on-change no Patient impede dado novo
# inválido daqui pra frente).
#
# Uso:
#   bundle exec rake patients:scan_invalid_contacts
#   bundle exec rake patients:scan_invalid_contacts ACCOUNT_ID=12485
namespace :patients do
  desc 'Lista pacientes com e-mail/telefone inválido (read-only, não altera nada)'
  task scan_invalid_contacts: :environment do
    scope = Patient.where(deleted_at: nil)
    if ENV['ACCOUNT_ID'].present?
      scope = scope.where(account_id: ENV['ACCOUNT_ID'])
      puts "Filtrando pela conta ##{ENV['ACCOUNT_ID']}."
    end

    by_account = Hash.new { |h, k| h[k] = [] }
    total = 0

    scope.find_each(batch_size: 500) do |patient|
      bad = []
      if patient.email.present? && !patient.email.strip.match?(Patient::EMAIL_FORMAT)
        bad << 'email'
      end
      bad << 'phone' if patient.phone.present? && !Patient.valid_phone_format?(patient.phone)
      next if bad.empty?

      total += 1
      by_account[patient.account_id] << {
        id: patient.id,
        name: patient.name,
        email: patient.email,
        phone: patient.phone,
        bad: bad
      }
    end

    if total.zero?
      puts 'Nenhum paciente com e-mail/telefone inválido. 🎉'
      next
    end

    puts "\n#{total} paciente(s) com contato inválido:\n\n"
    by_account.sort.each do |account_id, rows|
      puts "== Conta ##{account_id} (#{rows.size}) =="
      rows.each do |r|
        puts "  ##{r[:id]} #{r[:name]} — inválido: #{r[:bad].join(', ')} " \
             "| email=#{r[:email].inspect} phone=#{r[:phone].inspect}"
      end
      puts ''
    end
    puts "Total: #{total}. Correção é manual — não há como inferir o valor correto."
  end
end
