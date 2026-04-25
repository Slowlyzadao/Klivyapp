# frozen_string_literal: true

# rack-mini-profiler disabled: estava acumulando 1000+ arquivos em tmp/miniprofiler
# e causando erro 500 em todas as páginas (includes.js). Reativar se necessário:
# if Rails.env.development? && ENV['DISABLE_MINI_PROFILER'].blank?
#   require 'rack-mini-profiler'
#   Rack::MiniProfilerRails.initialize!(Rails.application)
# end
