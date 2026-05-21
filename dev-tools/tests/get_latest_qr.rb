c = Channel::Whatsapp.where(provider: 'whatsapp_qr').last
if c
  puts "LATEST_PHONE=#{c.phone_number}"
else
  puts "NO_CHANNEL_FOUND"
end
