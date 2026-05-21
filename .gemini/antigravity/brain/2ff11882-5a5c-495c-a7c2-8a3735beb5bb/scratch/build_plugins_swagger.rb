require 'json_refs'
require 'yaml'
require 'json'
require 'pathname'

swagger_dir = Pathname.new('/home/danilo/KlivyApp/swagger')
index_yml_path = swagger_dir.join('plugins_index.yml')
swagger_json_path = swagger_dir.join('plugins_swagger.json')

puts "Lendo #{index_yml_path}..."
swagger_index = YAML.safe_load(File.read(index_yml_path))

Dir.chdir(swagger_dir) do
  final_build = JsonRefs.call(
    swagger_index,
    resolve_local_ref: false,
    resolve_file_ref: true,
    logging: true
  )
  File.write(swagger_json_path, JSON.pretty_generate(final_build))
end

puts "Build concluído! Gerado em #{swagger_json_path}"
