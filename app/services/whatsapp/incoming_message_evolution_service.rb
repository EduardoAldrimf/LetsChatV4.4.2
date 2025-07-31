class Whatsapp::IncomingMessageEvolutionService < Whatsapp::IncomingMessageBaseService
  include Whatsapp::EvolutionHandlers::MessagesUpsert
  include Whatsapp::EvolutionHandlers::MessagesUpdate
  include Whatsapp::EvolutionHandlers::Helpers

  EVENT_HANDLERS = {
    'messages.upsert' => :process_messages_upsert,
    'messages.update' => :process_messages_update,
    'contacts.update' => :process_contacts_update,
    'qrcode.updated' => :handle_qrcode_updated,
    'connection.update' => :handle_connection_update
  }.freeze

  CHAT_EVENTS = %w[chats.update chats.upsert].freeze

  def perform
    event_type = processed_params[:event]

    Rails.logger.info "Evolution API: Processing event #{event_type} for instance #{processed_params[:instance]}"
    Rails.logger.debug { "Evolution API: Full payload: #{processed_params.inspect}" }

    if EVENT_HANDLERS.key?(event_type)
      send(EVENT_HANDLERS[event_type])
    elsif CHAT_EVENTS.include?(event_type)
      Rails.logger.info "Evolution API: Chat event #{event_type} - not processing (chat-level events)"
    else
      Rails.logger.warn "Evolution API: Unsupported event type: #{event_type}"
    end
  end

  def handle_qrcode_updated
    Dispatcher.dispatch(
      Events::Types::WHATSAPP_QRCODE_UPDATED,
      Time.current,
      inbox: inbox,
      qr_code: processed_params.dig(:data, :qrcode, :base64)
    )
  end

  def handle_connection_update
    status = processed_params.dig(:data, :state) ||
             processed_params.dig(:data, :connection_status) ||
             processed_params.dig(:data, :connectionStatus) ||
             processed_params.dig(:data, :status)
    status ||= 'close'

    inbox.channel.update_provider_connection!(connection: status)

    Dispatcher.dispatch(
      Events::Types::WHATSAPP_CONNECTION_UPDATE,
      Time.current,
      inbox: inbox,
      status: status
    )
  end

  def update_connection_status_from(data)
    data = data.first if data.is_a?(Array)
    return unless data.is_a?(Hash)

    status = data[:state] ||
             data[:connection_status] ||
             data[:connectionStatus] ||
             data[:status]
    return unless status

    inbox.channel.update_provider_connection!(connection: status)

    Dispatcher.dispatch(
      Events::Types::WHATSAPP_CONNECTION_UPDATE,
      Time.current,
      inbox: inbox,
      status: status
    )
  end

  private

  def processed_params
    @processed_params ||= params
  end

  def process_contacts_update
    # Evolution API sends contact updates when contact info changes (name, profile pic, etc.)
    contacts = processed_params[:data]
    contacts = [contacts] unless contacts.is_a?(Array)

    contacts.each do |contact_data|
      update_contact_info(contact_data)
    end

    # Some contact update events also include connection status information
    update_connection_status_from(processed_params[:data])
  end

  def update_contact_info(contact_data)
    remote_jid = contact_data[:remoteJid]
    return unless remote_jid

    phone_number = remote_jid.split('@').first
    push_name = contact_data[:pushName]
    profile_pic_url = contact_data[:profilePicUrl]

    # Find existing contact
    contact_inbox = inbox.contact_inboxes.find_by(source_id: phone_number)
    return unless contact_inbox

    contact = contact_inbox.contact

    # Update contact name if changed
    if push_name.present? && contact.name != push_name
      Rails.logger.info "Evolution API: Updating contact #{phone_number} name: #{contact.name} → #{push_name}"
      contact.update!(name: push_name)
    end

    # Update profile picture if url provided
    if profile_pic_url.present?
      Rails.logger.debug { "Evolution API: Contact #{phone_number} profile pic available: #{profile_pic_url}" }

      additional = contact.additional_attributes || {}
      stored_url = additional['social_whatsapp_profile_pic_url']

      if stored_url != profile_pic_url || !contact.avatar.attached?
        Rails.logger.info "Evolution API: Updating contact #{phone_number} avatar"
        contact.update!(additional_attributes: additional.merge('social_whatsapp_profile_pic_url' => profile_pic_url))
        Avatar::AvatarFromUrlJob.perform_later(contact, profile_pic_url)
      end
    end
  rescue StandardError => e
    Rails.logger.error "Evolution API: Failed to update contact info: #{e.message}"
  end
end
