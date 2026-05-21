json.payload do
  json.array! @form_templates do |template|
    json.partial! 'api/v1/accounts/form_templates/form_template', form_template: template
  end
end
