class Whatsapp::OneoffCampaignService
  pattr_initialize [:campaign!]

  def perform
    validate_campaign!
    # marks campaign completed so that other jobs won't pick it up
    campaign.completed!
    process_audience(extract_audience_labels)
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def validate_campaign_type!
    raise "Invalid campaign #{campaign.id}" unless whatsapp_campaign? && campaign.one_off?
  end

  def whatsapp_campaign?
    campaign.inbox.inbox_type == 'Whatsapp'
  end

  def validate_campaign_status!
    raise 'Completed Campaign' if campaign.completed?
  end

  def validate_provider!
    return if channel.provider == 'whatsapp_qr'
    raise 'WhatsApp Cloud provider required' if channel.provider != 'whatsapp_cloud'
  end

  def validate_feature_flag!
    raise 'WhatsApp campaigns feature not enabled' unless campaign.account.feature_enabled?(:whatsapp_campaign)
  end

  def validate_campaign!
    validate_campaign_type!
    validate_campaign_status!
    validate_provider!
    validate_feature_flag!
  end

  def extract_audience_labels
    audience_label_ids = campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
    campaign.account.labels.where(id: audience_label_ids).pluck(:title)
  end

  def process_contact(contact)
    Rails.logger.info "Processing contact: #{contact.name} (#{contact.phone_number})"

    is_group = contact.identifier.to_s.include?('@g.us')
    if contact.phone_number.blank? && !is_group
      Rails.logger.info "Skipping contact #{contact.name} - no phone number and not a group"
      return
    end

    recipient = is_group ? contact.identifier : contact.phone_number

    if channel.provider == 'whatsapp_qr'
      send_plain_text_message(to: recipient, contact: contact)
    else
      if campaign.template_params.blank?
        Rails.logger.error "Skipping contact #{contact.name} - no template_params found for WhatsApp campaign"
        return
      end
      send_whatsapp_template_message(to: recipient, contact: contact)
    end
  end

  def process_audience(audience_labels)
    contacts_from_tags = campaign.account.contacts.tagged_with(audience_labels, any: true).to_a
    contacts_from_conversations = campaign.account.conversations.tagged_with(audience_labels, any: true).includes(:contact).map(&:contact)

    all_contacts = (contacts_from_tags + contacts_from_conversations).uniq.compact
    Rails.logger.info "Processing #{all_contacts.count} contacts for campaign #{campaign.id}"

    all_contacts.each { |contact| process_contact(contact) }

    Rails.logger.info "Campaign #{campaign.id} processing completed"
  end

  def send_plain_text_message(to:, contact:)
    content = Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)
    contact_inbox = find_or_create_contact_inbox(contact)
    conversation = find_or_create_conversation(contact_inbox)
    message = conversation.messages.new(
      content: content,
      account_id: campaign.account_id,
      inbox_id: campaign.inbox_id,
      message_type: :outgoing,
      status: :sent,
      additional_attributes: { campaign_id: campaign.id }
    )
    message.source_id = "campaign_#{(Time.now.to_f * 1000).to_i}"
    message.save!

    source_id = channel.provider_service.send_text_message(to, content, message)
    message.update!(source_id: source_id) if source_id.present?
  rescue StandardError => e
    Rails.logger.error "Failed to send plain text message to #{to}: #{e.message}"
    nil
  end

  def send_whatsapp_template_message(to:, contact:)
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: campaign.template_params
    )

    name, namespace, lang_code, processed_parameters = processor.call

    return if name.blank?

    contact_inbox = find_or_create_contact_inbox(contact)
    conversation = find_or_create_conversation(contact_inbox)
    message = conversation.messages.new(
      content: campaign.message,
      account_id: campaign.account_id,
      inbox_id: campaign.inbox_id,
      message_type: :outgoing,
      status: :sent,
      additional_attributes: { campaign_id: campaign.id }
    )
    message.source_id = "campaign_#{(Time.now.to_f * 1000).to_i}"
    message.save!

    source_id = channel.send_template(to, {
                                        name: name,
                                        namespace: namespace,
                                        lang_code: lang_code,
                                        parameters: processed_parameters
                                      }, message)
    message.update!(source_id: source_id) if source_id.present?

  rescue StandardError => e
    Rails.logger.error "Failed to send WhatsApp template message to #{to}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
    # continue processing remaining contacts
    nil
  end

  def find_or_create_contact_inbox(contact)
    is_group = contact.identifier.to_s.include?('@g.us')
    if is_group
      source_id = contact.identifier.split('@').first
      ::ContactInboxWithContactBuilder.new(
        inbox: inbox,
        contact_attributes: {
          name: contact.name,
          identifier: contact.identifier
        },
        source_id: source_id
      ).perform
    else
      source_id = contact.phone_number.gsub(/\D/, '')
      ::ContactInboxWithContactBuilder.new(
        inbox: inbox,
        contact_attributes: {
          name: contact.name,
          phone_number: contact.phone_number,
          identifier: "#{source_id}@s.whatsapp.net"
        },
        source_id: source_id
      ).perform
    end
  end

  def find_or_create_conversation(contact_inbox)
    is_group = contact_inbox.contact.identifier.to_s.include?('@g.us')
    group_id = contact_inbox.contact.identifier.split('@').first if is_group

    conversation = contact_inbox.conversations.where.not(status: :resolved).last
    if conversation
      conversation.update!(campaign_id: campaign.id) if conversation.campaign_id.blank?
      if is_group && conversation.additional_attributes['group_id'].blank?
        conversation.additional_attributes['group_id'] = group_id
        conversation.save!
      end
    else
      conversation = campaign.account.conversations.create!(
        inbox_id: campaign.inbox_id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id,
        campaign_id: campaign.id,
        additional_attributes: group_id ? { 'group_id' => group_id } : {}
      )
    end
    conversation
  end
end
