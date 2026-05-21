json.left do
  json.partial! 'api/v1/accounts/patients/exam_medias/exam_media', exam_media: @left
end

json.right do
  json.partial! 'api/v1/accounts/patients/exam_medias/exam_media', exam_media: @right
end
