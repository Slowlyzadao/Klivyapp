json.data do
  json.array! @exams do |exam|
    json.partial! 'api/v1/accounts/patients/exam_medias/exam_media', exam_media: exam
  end
end

json.meta do
  json.total_count @exams.total_count
  json.current_page @exams.current_page
  json.total_pages @exams.total_pages
end
