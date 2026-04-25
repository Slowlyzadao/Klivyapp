require 'fileutils'

PROJECT_ROOT = File.expand_path('..', __dir__)
FRONTEND_DIR = File.join(PROJECT_ROOT, 'plugins/agenda/frontend')

def rewrite(file)
  content = File.read(file)
  changed = false

  # Fix ApiClient imports
  if content.include?("from './ApiClient'")
    content.gsub!("from './ApiClient'", "from 'dashboard/api/ApiClient'")
    changed = true
  end

  # Fix mutation-types imports
  if content.include?("from '../mutation-types'")
    content.gsub!("from '../mutation-types'", "from 'dashboard/store/mutation-types'")
    changed = true
  end

  # Fix Store's API relative imports: from '../../api/' -> from '../api/'
  if file.include?('/store/') && content.include?("from '../../api/")
    content.gsub!("from '../../api/", "from '../api/")
    changed = true
  end

  if changed
    File.write(file, content)
    puts "✅ Fixed imports in #{file.split(PROJECT_ROOT).last}"
  end
end

puts "🚀 Adjusting Vuex and API imports for Agenda Plugin..."
Dir.glob(File.join(FRONTEND_DIR, '**', '*.js')).each { |f| rewrite(f) }
Dir.glob(File.join(FRONTEND_DIR, '**', '*.vue')).each { |f| rewrite(f) }
puts "🎉 Done!"
