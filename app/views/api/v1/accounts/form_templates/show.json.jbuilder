json.payload do
  json.partial! 'api/v1/accounts/form_templates/form_template', form_template: @form_template
end
