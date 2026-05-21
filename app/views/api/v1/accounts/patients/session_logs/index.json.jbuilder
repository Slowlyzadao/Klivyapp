json.data do
  json.array! @session_logs do |session_log|
    json.partial! 'api/v1/accounts/patients/session_logs/session_log', session_log: session_log
  end
end

json.meta do
  json.current_page @session_logs.current_page
  json.total_pages  @session_logs.total_pages
  json.total_count  @session_logs.total_count
end
