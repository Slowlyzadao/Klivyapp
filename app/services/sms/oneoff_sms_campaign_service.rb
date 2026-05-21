class Sms::OneoffSmsCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" if campaign.inbox.inbox_type != 'Sms' || !campaign.one_off?
    raise 'Completed Campaign' if campaign.completed?

    # marks campaign completed so that other jobs won't pick it up
    campaign.completed!

    audience_label_ids = campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
    audience_labels = campaign.account.labels.where(id: audience_label_ids).pluck(:title)
    process_audience(audience_labels)
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def process_audience(audience_labels)
    contacts_from_tags = campaign.account.contacts.tagged_with(audience_labels, any: true).to_a
    contacts_from_conversations = campaign.account.conversations.tagged_with(audience_labels, any: true).includes(:contact).map(&:contact)

    all_contacts = (contacts_from_tags + contacts_from_conversations).uniq.compact

    all_contacts.each do |contact|
      next if contact.phone_number.blank?

      content = Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)
      send_message(to: contact.phone_number, contact: contact, content: content)
    end
  end

  def send_message(to:, contact:, content:)
    contact_inbox = find_or_create_contact_inbox(contact)
    conversation = find_or_create_conversation(contact_inbox)
    conversation.messages.create!(
      content: content,
      account_id: campaign.account_id,
      inbox_id: campaign.inbox_id,
      message_type: :outgoing,
      status: :sent,
      additional_attributes: { campaign_id: campaign.id }
    )

    channel.send_text_message(to, content)
  rescue StandardError => e
    Rails.logger.error("[SMS Campaign #{campaign.id}] Failed to send to #{to}: #{e.message}")
  end

  def find_or_create_contact_inbox(contact)
    source_id = contact.phone_number.gsub(/\D/, '')
    ::ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: {
        name: contact.name,
        phone_number: contact.phone_number
      },
      source_id: source_id
    ).perform
  end

  def find_or_create_conversation(contact_inbox)
    conversation = contact_inbox.conversations.where.not(status: :resolved).last
    if conversation
      conversation.update!(campaign_id: campaign.id) if conversation.campaign_id.blank?
    else
      conversation = campaign.account.conversations.create!(
        inbox_id: campaign.inbox_id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id,
        campaign_id: campaign.id
      )
    end
    conversation
  end
end
