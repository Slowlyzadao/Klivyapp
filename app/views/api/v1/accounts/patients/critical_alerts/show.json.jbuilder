json.payload do
  json.partial! 'api/v1/accounts/patients/critical_alerts/critical_alert', alert: @critical_alert
end
