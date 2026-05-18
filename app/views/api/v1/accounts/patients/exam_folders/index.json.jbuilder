json.data do
  json.array! @folders do |folder|
    json.partial! 'api/v1/accounts/patients/exam_folders/exam_folder', exam_folder: folder
  end
end
