begin
  puts "Testing Array#pluck:"
  data = [ {'id' => 1}, {'id' => 2} ]
  puts data.pluck('id').inspect
rescue => e
  puts "Failed: #{e.message}"
end
