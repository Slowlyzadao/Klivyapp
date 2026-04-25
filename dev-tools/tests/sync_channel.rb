#!/usr/bin/env ruby
require_relative 'config/environment'

channel = Channel::Whatsapp.where(provider: 'whatsapp_qr').last
if channel
  phone = channel.phone_number.to_s
  puts "Sincronizando phone_number #{phone} com o motor NodeJS..."
  system("curl -s -X POST http://localhost:3002/register -H 'Content-Type: application/json' -d '{\"phone_number\":\"#{phone}\"}'")
  puts "\nSincronização concluída."
else
  puts "Nenhum canal whatsapp_qr encontrado no database."
end
