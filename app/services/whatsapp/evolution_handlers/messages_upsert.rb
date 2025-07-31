require 'base64'
require 'tempfile'

module Whatsapp::EvolutionHandlers::MessagesUpsert
  include Whatsapp::EvolutionHandlers::Helpers
  include EvolutionHelper

  private

  def process_messages_upsert
    # Evolution API v2.3.1 sends single message data directly in 'data' field
    message_data = processed_params[:data]
    return if message_data.blank?

    @message = nil
    @contact_inbox = nil
    @contact = nil
    @raw_message = message_data

    Rails.logger.info "Evolution API: Processing message #{raw_message_id} (fromMe: #{!incoming?})"

    if incoming?
      handle_message
    else
      # Handle outgoing messages with lock to avoid race conditions
      with_evolution_channel_lock_on_outgoing_message(inbox.channel.id) { handle_message }
    end
  end

  def handle_message
    return if jid_type != 'user'
    return if ignore_message?
    return if find_message_by_source_id(raw_message_id) || message_under_process?

    Rails.logger.info "Evolution API: Creating new message #{raw_message_id}"

    cache_message_source_id_in_redis
    set_contact

    unless @contact
      clear_message_source_id_from_redis
      Rails.logger.warn "Evolution API: Contact not found for message: #{raw_message_id}"
      return
    end

    set_conversation
    handle_create_message
    clear_message_source_id_from_redis
  end

  def set_contact
    push_name = contact_name
    source_id = phone_number_from_jid

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: source_id,
      inbox: inbox,
      contact_attributes: {
        name: push_name,
        phone_number: "+#{source_id}",
        avatar_url: @raw_message[:profilePicUrl]
      }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact

    # Update contact name if it was just the phone number
    @contact.update!(name: push_name) if @contact.name == source_id && push_name.present?
    update_contact_avatar_from_message
  end

  def handle_create_message
    create_message(attach_media: has_media_attachment?)
  end

  def create_message(attach_media: false)
    @message = @conversation.messages.build(
      content: message_content || '',
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      source_id: raw_message_id,
      sender: incoming? ? @contact : @inbox.account.account_users.first.user,
      sender_type: incoming? ? 'Contact' : 'User',
      message_type: incoming? ? :incoming : :outgoing,
      content_attributes: message_content_attributes
    )

    handle_attach_media if attach_media
    handle_location if message_type == 'location'
    handle_contacts if message_type == 'contacts'

    @message.save!

    Rails.logger.info "Evolution API: Message created successfully - ID: #{@message.id}, Content: #{@message.content&.truncate(100)}"

    inbox.channel.received_messages([@message], @conversation) if incoming?
  end

  def message_content_attributes
    content_attributes = {
      external_created_at: evolution_extract_message_timestamp(@raw_message[:messageTimestamp])
    }

    quoted_id = extract_reply_to_id(@raw_message)
    content_attributes[:in_reply_to_external_id] = quoted_id if quoted_id.present?

    if message_type == 'reaction'
      content_attributes[:in_reply_to_external_id] = @raw_message.dig(:message, :reactionMessage, :key, :id)
      content_attributes[:is_reaction] = true
    elsif message_type == 'unsupported'
      content_attributes[:is_unsupported] = true
    end

    content_attributes
  end

  def handle_attach_media
    Rails.logger.info "Evolution API: Processing attachment for message #{raw_message_id}, type: #{message_type}"

    debug_media_info

    attachment_file = download_attachment_file

    return unless attachment_file

    # Use the enhanced filename and content_type for better reliability
    final_filename = generate_filename_with_extension
    final_content_type = determine_content_type

    Rails.logger.info 'Evolution API: Creating attachment with:'
    Rails.logger.info "  - Final filename: #{final_filename}"
    Rails.logger.info "  - Final content_type: #{final_content_type}"
    Rails.logger.info "  - File object class: #{attachment_file.class}"
    Rails.logger.info "  - File size: #{attachment_file.respond_to?(:size) ? attachment_file.size : 'unknown'}"

    attachment = @message.attachments.build(
      account_id: @message.account_id,
      file_type: file_content_type.to_s,
      file: {
        io: attachment_file,
        filename: final_filename,
        content_type: final_content_type
      }
    )

    # Mark audio as recorded if it's a voice note
    attachment.meta = { is_recorded_audio: true } if message_type == 'audio' && @raw_message.dig(:message, :audioMessage, :ptt)

    Rails.logger.info "Evolution API: Successfully created attachment for message #{raw_message_id}"
    Rails.logger.info "Evolution API: Attachment ID: #{attachment.id}, File attached: #{attachment.file.attached?}"

  rescue Down::Error => e
    @message.update!(is_unsupported: true)
    Rails.logger.error "Evolution API: Failed to download attachment for message #{raw_message_id}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Evolution API: Failed to create attachment for message #{raw_message_id}: #{e.message}"
    Rails.logger.error "  - Error class: #{e.class}"
    Rails.logger.error "  - Error details: #{e.inspect}"
  end

  def handle_location
    location_msg = @raw_message.dig(:message, :locationMessage) ||
                   @raw_message.dig(:message, :liveLocationMessage)
    return unless location_msg

    @message.content_attributes[:location] = {
      latitude: location_msg[:degreesLatitude],
      longitude: location_msg[:degreesLongitude],
      name: location_msg[:name],
      address: location_msg[:address]
    }

    location_name = if location_msg[:name].present?
                      "#{location_msg[:name]}, #{location_msg[:address]}"
                    else
                      ''
                    end

    @message.attachments.build(
      account_id: @message.account_id,
      file_type: file_content_type.to_s,
      coordinates_lat: location_msg[:degreesLatitude],
      coordinates_long: location_msg[:degreesLongitude],
      fallback_title: location_name,
      external_url: location_msg[:url]
    )
  end

  def handle_contacts
    contact_msg = @raw_message.dig(:message, :contactMessage)
    contacts_array = @raw_message.dig(:message, :contactsArrayMessage, :contacts)

    contacts = if contact_msg
                 [contact_msg]
               elsif contacts_array
                 contacts_array
               else
                 []
               end

    @message.content_attributes[:contacts] = contacts.map do |contact|
      {
        display_name: contact[:displayName],
        vcard: contact[:vcard]
      }
    end

    contacts.each do |contact|
      phones = contact_phones(contact)
      phones = [{ phone: 'Phone number is not available' }] if phones.blank?

      phones.each do |phone|
        @message.attachments.new(
          account_id: @message.account_id,
          file_type: file_content_type,
          fallback_title: phone[:phone].to_s,
          meta: { display_name: contact[:displayName] || contact[:display_name] }
        )
      end
    end
  end

  def update_contact_avatar_from_message
    profile_pic_url = @raw_message[:profilePicUrl]
    return if profile_pic_url.blank?

    additional = @contact.additional_attributes || {}
    stored_url = additional['social_whatsapp_profile_pic_url']

    return if stored_url == profile_pic_url && @contact.avatar.attached?

    Rails.logger.info "Evolution API: Updating avatar for contact #{@contact.id}"
    @contact.update!(additional_attributes: additional.merge('social_whatsapp_profile_pic_url' => profile_pic_url))
    ::Avatar::AvatarFromUrlJob.perform_later(@contact, profile_pic_url)
  end

  def download_attachment_file
    # Evolution API provides media in two ways:
    # 1. base64 - encoded directly in message.base64
    # 2. mediaUrl - URL for download in message.mediaUrl

    message = @raw_message[:message]

    # Try base64 first
    if message[:base64].present?
      Rails.logger.info 'Evolution API: Processing base64 attachment'
      return create_tempfile_from_base64(message[:base64])
    end

    # Try mediaUrl
    if message[:mediaUrl].present?
      Rails.logger.info "Evolution API: Downloading from mediaUrl: #{message[:mediaUrl]}"
      return Down.download(message[:mediaUrl], headers: inbox.channel.api_headers)
    end

    Rails.logger.warn 'Evolution API: No media found - no base64 or mediaUrl'
    nil
  rescue StandardError => e
    Rails.logger.error "Evolution API: Failed to download media: #{e.message}"
    nil
  end

  def create_tempfile_from_base64(base64_data)
    # Evolution API pode enviar base64 com ou sem prefixo
    base64_clean = base64_data.gsub(/^data:.*?;base64,/, '')

    # Decodifica o base64
    decoded_data = Base64.decode64(base64_clean)

    # Determine content type and filename
    content_type = determine_content_type
    file_name = generate_filename_with_extension

    Rails.logger.info 'Evolution API: Creating attachment from base64'
    Rails.logger.info "  - Size: #{decoded_data.bytesize} bytes"
    Rails.logger.info "  - Content-Type: #{content_type}"
    Rails.logger.info "  - Filename: #{file_name}"

    # Cria um arquivo temporário
    tempfile = Tempfile.new([raw_message_id, file_extension])
    tempfile.binmode
    tempfile.write(decoded_data)
    tempfile.rewind

    # Simula um objeto Down::File para compatibilidade
    tempfile.define_singleton_method(:original_filename) do
      file_name
    end

    tempfile.define_singleton_method(:content_type) do
      content_type
    end

    # Adiciona método size para compatibilidade
    tempfile.define_singleton_method(:size) do
      File.size(path)
    end

    Rails.logger.info "Evolution API: Successfully created tempfile: #{tempfile.path}"
    Rails.logger.info "Evolution API: Tempfile size: #{tempfile.size} bytes"

    tempfile
  rescue StandardError => e
    Rails.logger.error "Evolution API: Failed to create file from base64: #{e.message}"
    Rails.logger.error "  - Base64 size: #{base64_data&.length || 0} chars"
    Rails.logger.error "  - Message type: #{message_type}"
    Rails.logger.error "  - Raw mimetype: #{message_mimetype}"
    nil
  end

  def file_extension
    case message_type
    when 'image'
      case message_mimetype
      when /jpeg/
        '.jpg'
      when /png/
        '.png'
      when /gif/
        '.gif'
      when /webp/
        '.webp'
      else
        '.jpg'
      end
    when 'video'
      case message_mimetype
      when /mp4/
        '.mp4'
      when /webm/
        '.webm'
      when /avi/
        '.avi'
      else
        '.mp4'
      end
    when 'audio'
      case message_mimetype
      when /mp3/
        '.mp3'
      when /wav/
        '.wav'
      when /ogg/
        '.ogg'
      when /aac/
        '.aac'
      when /opus/
        '.opus'
      else
        '.mp3'
      end
    when 'file'
      filename_from_message = @raw_message.dig(:message, :documentMessage, :fileName) ||
                              @raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :fileName)
      return File.extname(filename_from_message) if filename_from_message.present?

      case message_mimetype
      when /pdf/
        '.pdf'
      when /doc/
        '.doc'
      when /zip/
        '.zip'
      else
        '.bin'
      end
    when 'sticker'
      '.webp'
    else
      '.bin'
    end
  end

  def debug_media_info
    message = @raw_message[:message]
    Rails.logger.info 'Evolution API: Media processing debug:'
    Rails.logger.info "  Message Type: #{message_type}"
    Rails.logger.info "  Has Base64: #{message[:base64].present?}"
    Rails.logger.info "  Has MediaUrl: #{message[:mediaUrl].present?}"
    Rails.logger.info "  MimeType: #{message_mimetype}"
    Rails.logger.info "  Filename: #{filename}"
    Rails.logger.info "  File Extension: #{file_extension}"
  end

  def determine_content_type
    # Primeiro tenta usar o mimetype da mensagem
    mime = message_mimetype
    return mime if mime.present?

    # Fallback baseado no tipo de mensagem
    case message_type
    when 'image'
      'image/jpeg'
    when 'video'
      'video/mp4'
    when 'audio'
      'audio/mpeg'
    when 'file'
      'application/octet-stream'
    when 'sticker'
      'image/webp'
    else
      'application/octet-stream'
    end
  end

  def generate_filename_with_extension
    # Primeiro tenta usar o filename da mensagem
    existing_filename = filename

    # Se já tem extensão, usa como está
    return existing_filename if existing_filename.present? && File.extname(existing_filename).present?

    # Senão, gera um nome com extensão baseada no tipo
    base_name = existing_filename.presence || "#{message_type}_#{raw_message_id}_#{Time.current.strftime('%Y%m%d')}"
    extension = file_extension

    "#{base_name}#{extension}"
  end
end
