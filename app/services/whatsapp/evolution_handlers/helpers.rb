module Whatsapp::EvolutionHandlers::Helpers
  include Whatsapp::IncomingMessageServiceHelpers

  private

  def raw_message_id
    # Evolution events sometimes include both :messageId and :keyId. The message
    # is stored using the key id, so prefer that when available.
    @raw_message[:keyId] || @raw_message[:messageId] || @raw_message.dig(:key, :id)
  end

  def incoming?
    # Para messages.update, fromMe vem diretamente no root
    if @raw_message[:fromMe].present?
      !@raw_message[:fromMe]
    elsif @raw_message.dig(:key, :fromMe).present?
      !@raw_message[:key][:fromMe]
    else
      # Se não conseguir determinar, assumir que é incoming para evitar erro
      Rails.logger.warn 'Evolution API: Unable to determine message direction, assuming incoming'
      true
    end
  end

  def message_type
    msg = @raw_message[:message]
    return 'text' unless msg

    if msg[:conversation] || msg.dig(:extendedTextMessage, :text).present?
      'text'
    elsif msg[:imageMessage]
      'image'
    elsif msg[:audioMessage]
      'audio'
    elsif msg[:videoMessage]
      'video'
    elsif msg[:documentMessage] || msg[:documentWithCaptionMessage]
      'file'
    elsif msg[:stickerMessage]
      'sticker'
    elsif msg[:reactionMessage]
      'reaction'
    elsif msg[:locationMessage] || msg[:liveLocationMessage]
      'location'
    elsif msg[:contactMessage] || msg[:contactsArrayMessage]
      'contacts'
    elsif msg[:protocolMessage]
      'protocol'
    else
      'unsupported'
    end
  end

  def message_content
    case message_type
    when 'text'
      @raw_message.dig(:message, :conversation) || @raw_message.dig(:message, :extendedTextMessage, :text)
    when 'image'
      @raw_message.dig(:message, :imageMessage, :caption)
    when 'video'
      @raw_message.dig(:message, :videoMessage, :caption)
    when 'file'
      @raw_message.dig(:message, :documentMessage, :caption) ||
        @raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :caption)
    when 'reaction'
      @raw_message.dig(:message, :reactionMessage, :text)
    when 'location'
      # No textual content for location messages. The LocationBubble will be
      # rendered based on the attachment.
      nil
    when 'contacts'
      # Extract contact name for display and include phone numbers
      contact_msg = @raw_message.dig(:message, :contactMessage) ||
                    @raw_message.dig(:message, :contactsArrayMessage, :contacts)&.first
      return 'Contact' if contact_msg.blank?

      name = contact_msg[:displayName] || contact_msg[:vcard]&.match(/FN:(.+)/i)&.[](1) || 'Contact'
      numbers = contact_phones(contact_msg)&.map { |p| p[:phone] } || []

      numbers.present? ? "#{name}\n#{numbers.join("\n")}" : name
    end
  end

  def file_content_type
    return :image if message_type.in?(%w[image sticker])
    return :video if message_type == 'video'
    return :audio if message_type == 'audio'
    return :location if message_type == 'location'
    return :contact if message_type == 'contacts'

    :file
  end

  def message_mimetype
    case message_type
    when 'image'
      @raw_message.dig(:message, :imageMessage, :mimetype)
    when 'sticker'
      @raw_message.dig(:message, :stickerMessage, :mimetype)
    when 'video'
      @raw_message.dig(:message, :videoMessage, :mimetype)
    when 'audio'
      @raw_message.dig(:message, :audioMessage, :mimetype)
    when 'file'
      @raw_message.dig(:message, :documentMessage, :mimetype) ||
        @raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :mimetype)
    end
  end

  def phone_number_from_jid
    # Evolution API format: "5511999999999@s.whatsapp.net" or "5511999999999@c.us"
    # Para messages.update, remoteJid pode vir diretamente no root
    remote_jid = @raw_message[:remoteJid] || @raw_message.dig(:key, :remoteJid)
    return nil unless remote_jid

    remote_jid.split('@').first.split(':').first.split('_').first
  end

  def contact_name
    # Evolution API provides pushName
    name = @raw_message[:pushName].presence
    return name if incoming?

    phone_number_from_jid
  end

  def evolution_extract_message_timestamp(timestamp)
    # Evolution API timestamp is usually in seconds or milliseconds
    timestamp = timestamp.to_i

    # If timestamp looks like it's in milliseconds (> 10^12), convert to seconds
    timestamp /= 1000 if timestamp > 10**12

    # Return Unix timestamp as integer (like baileys_extract_message_timestamp)
    timestamp
  rescue StandardError
    Time.current.to_i
  end

  def filename
    filename = @raw_message.dig(:message, :documentMessage, :fileName) ||
               @raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :fileName)
    return filename if filename.present?

    ext = ".#{message_mimetype.split(';').first.split('/').last}" if message_mimetype.present?
    "#{file_content_type}_#{raw_message_id}_#{Time.current.strftime('%Y%m%d')}#{ext}"
  end

  def ignore_message?
    # Skip unsupported message types
    return true if message_type.in?(%w[protocol unsupported])

    # Skip if no content available
    return true if message_content.blank? && !has_media_attachment?

    false
  end

  def has_media_attachment?
    %w[image video audio file sticker location].include?(message_type)
  end

  def self_message?
    # Para messages.update, fromMe pode vir diretamente no root
    @raw_message[:fromMe] || @raw_message.dig(:key, :fromMe) || false
  end

  def jid_type
    # Para messages.update, remoteJid pode vir diretamente no root
    jid = @raw_message[:remoteJid] || @raw_message.dig(:key, :remoteJid)
    return 'unknown' unless jid

    server = jid.split('@').last

    # Based on Evolution API JID patterns
    case server
    when 's.whatsapp.net', 'c.us'
      'user'
    when 'g.us'
      'group'
    when 'lid'
      'lid'
    when 'broadcast'
      jid.start_with?('status@') ? 'status' : 'broadcast'
    when 'newsletter'
      'newsletter'
    when 'call'
      'call'
    else
      'unknown'
    end
  end
end
