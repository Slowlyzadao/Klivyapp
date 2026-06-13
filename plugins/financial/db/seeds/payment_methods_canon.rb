# Seeds dos meios de pagamento padrão conforme canon `mapa-financeiro.json`
# step 3. Cria 1 entrada por `kind` canon — a clínica edita nomes ("Cielo
# Crédito" em vez de "Cartão de Crédito") e adiciona variantes.
#
# Também cria fees iniciais (taxa zero) em `financial_payment_method_fees`
# pra dinheiro, pix, transferência e parcelamento próprio. Crédito e débito
# começam SEM fee — clínica precisa cadastrar pra cada adquirente + parcela
# (canon: "Geradas automaticamente ao registrar recebimento; nunca lançar
# manualmente.").
#
# Executar:
#   docker exec beclinic-rails-1 bundle exec rails runner \
#     'plugins/financial/db/seeds/payment_methods_canon.rb' [account_id]

account_id = ARGV[0]&.to_i || ::Account.first&.id
raise 'Conta inexistente' if account_id.nil?

account = ::Account.find(account_id)
puts "Seeding payment methods canon para Account ##{account.id}"

# Definição canon: (kind, default_name, supports_installments?, max_installments)
canon = [
  ['dinheiro',             'Dinheiro',                 false, 1],
  ['pix',                  'Pix',                      false, 1],
  ['debito',               'Débito',                   false, 1],
  ['credito',              'Crédito',                  true,  12],
  ['boleto',               'Boleto',                   false, 1],
  ['transferencia',        'Transferência Bancária',   false, 1],
  ['convenio',             'Convênio',                 false, 1],
  ['parcelamento_proprio', 'Parcelamento da Clínica',  true,  24]
]

today = Date.current

canon.each do |kind, name, supports, max|
  pm = ::Financial::PaymentMethod.alive.find_by(account_id: account.id, kind: kind, name: name)
  if pm
    puts "  ⏭️  Já existe: #{name}"
  else
    pm = ::Financial::PaymentMethod.create!(
      account_id: account.id,
      kind: kind,
      name: name,
      supports_installments: supports,
      max_installments: max,
      status: 'active'
    )
    puts "  ✅ Criado: #{name} (max #{max} parcelas)"
  end

  # Fees padrão (taxa zero) pra métodos sem taxa
  if %w[dinheiro pix transferencia parcelamento_proprio].include?(kind)
    fee = pm.payment_method_fees.alive.find_by(installments_count: 1, valid_from: today)
    unless fee
      pm.payment_method_fees.create!(
        account_id: account.id,
        installments_count: 1,
        fee_percent_basis_points: 0,
        fee_fixed_cents: 0,
        liquidation_days: kind == 'transferencia' ? 1 : 0,
        valid_from: today,
        status: 'active'
      )
      puts "      └─ Fee zero criada (D+#{kind == 'transferencia' ? 1 : 0})"
    end
  end
end

puts "\n✅ Payment methods canon seed completo"
puts "Próximo passo: cadastrar fees de crédito/débito/boleto em /financial/v2/settings"
