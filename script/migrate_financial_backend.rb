require 'fileutils'
require 'pathname'

root = Pathname.new(__dir__).join('..')
plugin_root = root.join('plugins/financial/app')

models_to_move = %w[
  account_transaction.rb
  bank_account.rb
  cash_entry.rb
  cash_register.rb
  cash_register_entry.rb
  category.rb
  commission_rule.rb
  financial_category.rb
  financial_estimate.rb
  installment.rb
  recurring_expense.rb
  transaction.rb
]

puts "🚀 Migrating Financial Backend Files to Plugin..."

# Garantir a criacao do diretorio models
FileUtils.mkdir_p(plugin_root.join('models'))

models_to_move.each do |model|
  src = root.join('app/models', model)
  dest = plugin_root.join('models', model)
  if src.exist?
    FileUtils.mv(src, dest)
    puts "✅ Moved #{model} to plugin"
  else
    puts "⚠️ #{model} not found in core"
  end
end

# Controladores
controllers_to_move = %w[
  account_transactions_controller.rb
  bank_accounts_controller.rb
  cash_registers_controller.rb
  categories_controller.rb
  commission_rules_controller.rb
  financial_categories_controller.rb
  financial_dashboard_controller.rb
  financial_goals_controller.rb
  financial_pdfs_controller.rb
  financial_reports_controller.rb
  recurring_expenses_controller.rb
]

controllers_base = root.join('app/controllers/api/v1/accounts')
dest_controllers_dir = plugin_root.join('controllers/api/v1/accounts')
FileUtils.mkdir_p(dest_controllers_dir)

controllers_to_move.each do |ctrl|
  src = controllers_base.join(ctrl)
  dest = dest_controllers_dir.join(ctrl)
  if src.exist?
    FileUtils.mv(src, dest)
    puts "✅ Moved #{ctrl} to plugin"
  else
    puts "⚠️ #{ctrl} not found in core"
  end
end

puts "🎉 Backend separation scripts completed!"
