json.payload do
  json.array! @critical_alerts do |alert|
    json.partial! 'api/v1/accounts/patients/critical_alerts/critical_alert', alert: alert
  end
end
