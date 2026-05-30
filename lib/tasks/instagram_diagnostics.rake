namespace :instagram do
  desc 'Audit Instagram inboxes: list channels, check tokens, verify Meta subscriptions. Usage: rake instagram:diagnose ACCOUNT_ID=1 (optional)'
  task diagnose: :environment do
    account_id = ENV['ACCOUNT_ID'].presence&.to_i

    puts '=' * 80
    puts 'INSTAGRAM INBOX DIAGNOSTICS'
    puts "Account filter: #{account_id || 'ALL ACCOUNTS'}"
    puts "Generated at: #{Time.current.iso8601}"
    puts '=' * 80

    print_env_vars
    print_instagram_channels(account_id)
    print_facebook_page_channels(account_id)

    puts "\nDone. To watch incoming webhooks in real time:"
    puts "  tail -f log/development.log | grep IG_AUDIT"
  end

  def print_env_vars
    puts "\n--- Env vars (presence check, values redacted) ---"
    keys = %w[FB_APP_ID FB_APP_SECRET FB_VERIFY_TOKEN IG_VERIFY_TOKEN
              INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN
              INSTAGRAM_API_VERSION FACEBOOK_API_VERSION]
    keys.each do |k|
      val = GlobalConfigService.load(k, nil)
      status = val.present? ? "SET (len=#{val.to_s.length})" : 'MISSING'
      puts "  #{k.ljust(28)} #{status}"
    end
  end

  def print_instagram_channels(account_id)
    puts "\n--- Channel::Instagram (Instagram Login direto) ---"
    scope = Channel::Instagram.all
    scope = scope.where(account_id: account_id) if account_id
    channels = scope.to_a

    if channels.empty?
      puts '  (nenhum canal registrado)'
      return
    end

    channels.each { |c| dump_instagram_channel(c) }
  end

  def print_facebook_page_channels(account_id)
    puts "\n--- Channel::FacebookPage com instagram_id (Instagram via FB Page) ---"
    scope = Channel::FacebookPage.where.not(instagram_id: nil)
    scope = scope.where(account_id: account_id) if account_id
    channels = scope.to_a

    if channels.empty?
      puts '  (nenhuma página com Instagram conectado)'
      return
    end

    channels.each { |c| dump_facebook_channel(c) }
  end

  def dump_instagram_channel(c)
    inbox = c.inbox
    puts "\n  [Channel::Instagram ##{c.id}]"
    puts "    account_id:               #{c.account_id}"
    puts "    instagram_id:             #{c.instagram_id}"
    puts "    inbox:                    #{inbox ? "##{inbox.id} '#{inbox.name}'" : 'NENHUMA INBOX!! (canal órfão)'}"
    puts "    expires_at:               #{c.expires_at} (#{token_status(c.expires_at)})"
    puts "    reauthorization_required: #{c.reauthorization_required? ? 'SIM <- causa provável' : 'não'}"
    puts "    contact_inboxes count:    #{inbox&.contact_inboxes&.count || 0}"
    puts "    last conversation:        #{last_conversation_summary(inbox)}"
    check_subscription(c.instagram_id, c.access_token, 'https://graph.instagram.com/v22.0')
  rescue StandardError => e
    puts "    ERRO ao inspecionar canal: #{e.class.name}: #{e.message}"
  end

  def dump_facebook_channel(c)
    inbox = c.inbox
    puts "\n  [Channel::FacebookPage ##{c.id}]"
    puts "    account_id:               #{c.account_id}"
    puts "    page_id:                  #{c.page_id}"
    puts "    instagram_id:             #{c.instagram_id}"
    puts "    inbox:                    #{inbox ? "##{inbox.id} '#{inbox.name}'" : 'NENHUMA INBOX!! (canal órfão)'}"
    puts "    reauthorization_required: #{c.reauthorization_required? ? 'SIM <- causa provável' : 'não'}"
    puts "    contact_inboxes count:    #{inbox&.contact_inboxes&.count || 0}"
    puts "    last conversation:        #{last_conversation_summary(inbox)}"
  rescue StandardError => e
    puts "    ERRO ao inspecionar canal: #{e.class.name}: #{e.message}"
  end

  def token_status(expires_at)
    return 'sem expires_at' if expires_at.blank?
    return "EXPIRADO há #{((Time.current - expires_at) / 1.day).round}d" if expires_at < Time.current
    return "expira em #{((expires_at - Time.current) / 1.day).round}d (renovar logo)" if expires_at < 7.days.from_now

    "expira em #{((expires_at - Time.current) / 1.day).round}d"
  end

  def last_conversation_summary(inbox)
    return 'n/a (sem inbox)' if inbox.blank?

    conv = inbox.conversations.order(created_at: :desc).first
    return 'NUNCA recebeu mensagem' if conv.blank?

    "##{conv.id} criada em #{conv.created_at.iso8601} (status=#{conv.status})"
  end

  def check_subscription(instagram_id, access_token, base_url)
    require 'httparty'
    res = HTTParty.get(
      "#{base_url}/#{instagram_id}/subscribed_apps",
      query: { access_token: access_token },
      timeout: 8
    )
    if res.code == 200
      fields = res.parsed_response.dig('data')&.flat_map { |a| a['subscribed_fields'] }&.uniq
      puts "    subscribed_apps OK:       fields=#{fields.inspect}"
      puts '    WARN: subscription sem campo "messages"!' if fields && !fields.include?('messages')
    else
      puts "    subscribed_apps ERROR:    HTTP #{res.code} body=#{res.body.to_s[0, 300]}"
    end
  rescue StandardError => e
    puts "    subscribed_apps EXCEPTION: #{e.class.name}: #{e.message}"
  end
end
