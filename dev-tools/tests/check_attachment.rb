message = Message.where("attachments IS NOT NULL").last
if message && message.attachments.any?
  puts "URL:#{message.attachments.first.download_url}"
  puts "TYPE:#{message.attachments.first.file_type}"
else
  puts "NO_ATTACHMENT_FOUND"
end
