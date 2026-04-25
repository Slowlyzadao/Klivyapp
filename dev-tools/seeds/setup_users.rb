account = Account.find_by(id: 1) || Account.first
account.update!(name: 'Beclinic') if account

users = [
  { name: 'Leandro', email: 'leandro@beclinic.com', role: 'administrator' },
  { name: 'Gabriel', email: 'gabriel@beclinic.com', role: 'administrator' },
  { name: 'Wilson', email: 'wilson@beclinic.com', role: 'agent' },
  { name: 'Gustavo', email: 'gustavo@beclinic.com', role: 'agent' },
  { name: 'Felipe', email: 'felipe@beclinic.com', role: 'agent' }
]

users.each do |u_data|
  user = User.find_or_initialize_by(email: u_data[:email])
  user.name = u_data[:name]
  user.password = '123456'
  user.password_confirmation = '123456'
  user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
  user.save!
  
  au = AccountUser.find_or_initialize_by(account_id: account.id, user_id: user.id)
  au.role = u_data[:role]
  au.save!
end

puts "Users processed successfully!"
