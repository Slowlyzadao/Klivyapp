log = File.read("log/development.log")
block = log.split("Started PUT").last
puts "Started PUT" + block.split("Completed 500").first + "Completed 500" + block.split("Completed 500")[1].lines.first(20).join
