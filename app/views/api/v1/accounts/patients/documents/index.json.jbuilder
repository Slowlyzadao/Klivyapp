json.data do
  json.array! @documents do |document|
    json.partial! 'api/v1/accounts/patients/documents/document', document: document
  end
end

json.meta do
  json.total_count @documents.total_count
  json.current_page @documents.current_page
  json.total_pages @documents.total_pages
end
