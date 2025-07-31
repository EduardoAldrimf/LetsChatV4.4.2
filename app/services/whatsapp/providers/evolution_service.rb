require 'base64'

class Whatsapp::Providers::EvolutionService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message
    @phone_number = phone_number

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content.present?
      send_text_message(phone_number, message)
    else
      @message.update!(is_unsupported: true)
      return
    end
  end

  def send_template(phone_number, template_info)
    # Evolution API doesn't support template messages in the same way
    # For now, we'll send a regular text message
    Rails.logger.warn "Evolution API doesn't support template messages, sending as text"
    send_text_message(phone_number, build_template_text(template_info))
  end

  def sync_templates
    # Evolution API doesn't have template syncing like WhatsApp Cloud
    # Mark as updated to prevent continuous sync attempts
    whatsapp_channel.mark_message_templates_updated
  end

  def validate_provider_config?
    return false if api_base_path.blank?
    return false if admin_token.blank?
    return false if instance_name.blank?

    # Test connection to Evolution API root endpoint
    response = HTTParty.get(
      api_base_path,
      headers: api_headers,
      timeout: 10
    )

    response.success? && response.parsed_response['status'] == 200
  rescue StandardError => e
    Rails.logger.error "Evolution API validation error: #{e.message}"
    false
  end

  def api_headers
    {
      'apikey' => admin_token,
      'Content-Type' => 'application/json'
    }
  end

  def media_url(media_id)
    # Evolution API media endpoint
    "#{api_base_path}/media/#{media_id}"
  end

  def subscribe_to_webhooks
    # Evolution API webhook subscription if needed
    Rails.logger.info 'Evolution API webhook subscription not implemented'
  end

  def unsubscribe_from_webhooks
    # Evolution API webhook unsubscription if needed
    Rails.logger.info 'Evolution API webhook unsubscription not implemented'
  end

  private

  def api_base_path
    (whatsapp_channel.provider_config['api_url'].presence || ENV.fetch('EVOLUTION_API_URL', nil)).to_s.chomp('/')
  end

  def admin_token
    whatsapp_channel.provider_config['admin_token'].presence || ENV.fetch('EVOLUTION_ADMIN_TOKEN', nil)
  end

  def instance_name
    whatsapp_channel.provider_config['instance_name'].presence || ENV.fetch('EVOLUTION_INSTANCE_NAME', nil)
  end

  def evolution_reply_context(message)
    reply_to = message.content_attributes[:in_reply_to_external_id]
    return {} if reply_to.blank?

    {
      contextInfo: {
        stanzaId: reply_to,
        quotedMessage: { key: { id: reply_to } }
      },
      context: { id: reply_to },
      quoted: { key: { id: reply_to } },
      quotedMsgId: reply_to
    }
  end

  def send_text_message(phone_number, message)
    body_data = {
      number: phone_number.delete('+'),
      text: message.respond_to?(:content) ? message.content : message.to_s
    }.merge(evolution_reply_context(message))

    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{instance_name}",
      headers: api_headers,
      body: body_data.to_json
    )

    process_response(response)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    return unless attachment

    case attachment.file_type
    when 'image', 'video', 'file'
      send_media_message(phone_number, message, 'sendMedia')
    when 'audio'
      send_audio_message(phone_number, message)
    else
      # Fallback to text message
      send_text_message(phone_number, message)
    end
  end

  def send_media_message(phone_number, message, endpoint)
    attachment = message.attachments.first

    # Use direct S3 URL for media
    media_url = generate_direct_s3_url(attachment)

    Rails.logger.info "[Evolution Media] Sending #{attachment.file_type} with direct URL: #{media_url}"

    mediatype = attachment.file_type
    mediatype = 'document' if mediatype == 'file'

    body_data = {
      number: phone_number.delete('+'),
      mediatype: mediatype,
      media: media_url,
      caption: message.content.to_s,
      fileName: attachment.file.filename.to_s
    }.merge(evolution_reply_context(message))

    response = HTTParty.post(
      "#{api_base_path}/message/#{endpoint}/#{instance_name}",
      headers: api_headers,
      body: body_data.to_json
    )

    process_response(response)
  end

  def send_audio_message(phone_number, message)
    attachment = message.attachments.first

    # Try direct public URL first (for public S3 buckets)
    result = send_audio_with_direct_url(phone_number, attachment, message)

    # If direct URL fails, try base64
    if !result && attachment.file.attached?
      Rails.logger.info '[Evolution Audio] Direct URL failed, trying base64'
      result = send_audio_with_base64(phone_number, attachment, message)
    end

    result
  end

  def send_audio_with_direct_url(phone_number, attachment, message)
    # Generate direct public URL for S3 bucket
    audio_url = generate_direct_s3_url(attachment)

    # Debug log
    Rails.logger.info "[Evolution Audio] Trying direct URL: #{audio_url}"

    body_data = {
      number: phone_number.delete('+'),
      audio: audio_url
    }.merge(evolution_reply_context(message))

    Rails.logger.info "[Evolution Audio] Request body: #{body_data.to_json}"

    response = HTTParty.post(
      "#{api_base_path}/message/sendWhatsAppAudio/#{instance_name}",
      headers: api_headers,
      body: body_data.to_json,
      timeout: 60
    )

    Rails.logger.info "[Evolution Audio] Response status: #{response.code}"
    Rails.logger.info "[Evolution Audio] Response body: #{response.body}"

    process_response(response)
  end

  def generate_direct_s3_url(attachment)
    return attachment.file_url unless attachment.file.attached?

    # Extract S3 details from existing signed URL
    signed_url = attachment.download_url

    Rails.logger.info "[Evolution S3] Original signed URL: #{signed_url}"
    return signed_url unless ENV['EVOLUTION_PUBLIC_S3'] == 'true'

    # Try to extract bucket and key from the signed URL (flexible regex for different S3 providers)
    if signed_url =~ %r{https://([^/]+)/([^?]+)}
      host = ::Regexp.last_match(1)
      key = ::Regexp.last_match(2)

      # Create direct public URL - just remove query parameters
      direct_url = "https://#{host}/#{key}"
      Rails.logger.info "[Evolution S3] Generated direct URL: #{direct_url}"
      return direct_url
    end

    # Fallback to original URL if can't parse
    Rails.logger.warn "[Evolution S3] Could not parse S3 URL, using original: #{signed_url}"
    signed_url
  end

  def send_audio_with_base64(phone_number, attachment, message)
    # Convert to base64 - Evolution API expects just the base64 string
    buffer = Base64.strict_encode64(attachment.file.download)

    Rails.logger.info "[Evolution Audio] Trying base64 (size: #{buffer.length})"

    body_data = {
      number: phone_number.delete('+'),
      audio: buffer # Just the base64 string, no data URI prefix
    }.merge(evolution_reply_context(message))

    response = HTTParty.post(
      "#{api_base_path}/message/sendWhatsAppAudio/#{instance_name}",
      headers: api_headers,
      body: body_data.to_json,
      timeout: 60
    )

    Rails.logger.info "[Evolution Audio] Base64 Response status: #{response.code}"
    Rails.logger.info "[Evolution Audio] Base64 Response body: #{response.body}"

    process_response(response)
  end

  def build_template_text(template_info)
    # Convert template info to plain text for Evolution API
    text = template_info[:name] || 'Template Message'
    if template_info[:parameters].present?
      template_info[:parameters].each_with_index do |param, index|
        text = text.gsub("{{#{index + 1}}}", param)
      end
    end
    text
  end

  def process_response(response)
    if response.success?
      parsed_response = response.parsed_response
      return parsed_response.dig('key', 'id') || parsed_response['messageId'] || true
    end

    Rails.logger.error "Evolution API error: #{response.code} - #{response.body}"
    false
  end

  def setup_channel_provider
    whatsapp_channel.provider_config['api_url'] ||= ENV.fetch('EVOLUTION_API_URL', nil)
    whatsapp_channel.provider_config['admin_token'] ||= ENV.fetch('EVOLUTION_ADMIN_TOKEN', nil)
    whatsapp_channel.save! if whatsapp_channel.changed?
    response = HTTParty.post(
      "#{api_base_path}/instance/create",
      headers: api_headers,
      body: {
        instanceName: instance_name,
        number: whatsapp_channel.phone_number.delete('+'),
        integration: 'WHATSAPP-BAILEYS',
        qrcode: false,
        byEvents: false,
        base64: true,
        webhook: {
          url: "#{ENV.fetch('FRONTEND_URL', nil)}/webhooks/whatsapp/#{whatsapp_channel.phone_number}",
          events: %w[
            QRCODE_UPDATED
            MESSAGES_SET
            MESSAGES_UPSERT
            MESSAGES_UPDATE
            MESSAGES_DELETE
            SEND_MESSAGE
            CONTACTS_SET
            CONTACTS_UPDATE
            PRESENCE_UPDATE
            CONNECTION_UPDATE
          ]
        }
      }.to_json
    )

    if response.success?
      whatsapp_channel.update_provider_connection!(response.parsed_response)
    else
      Rails.logger.error "Evolution API setup error: #{response.code} - #{response.body}"
    end
  rescue StandardError => e
    Rails.logger.error "Evolution API setup exception: #{e.message}"
  end

  def configure_webhook
    return unless whatsapp_channel.inbox

    webhook_url = "#{ENV.fetch('FRONTEND_URL', nil)}/evolution/webhooks/#{whatsapp_channel.inbox.id}"
    response = HTTParty.post(
      "#{api_base_path}/webhook/set/#{instance_name}",
      headers: api_headers,
      body: { webhook: { url: webhook_url, events: %w[messages.upsert messages.update] } }.to_json
    )

    Rails.logger.error "Evolution API webhook error: #{response.code} - #{response.body}" unless response.success?
  rescue StandardError => e
    Rails.logger.error "Evolution API webhook exception: #{e.message}"
  end

  def disconnect_channel_provider
    return if api_base_path.blank? || admin_token.blank? || instance_name.blank?

    delete_url = "#{api_base_path}/instance/delete/#{instance_name}"
    Rails.logger.info "Evolution API: Deleting instance at #{delete_url}"

    response = HTTParty.delete(delete_url, headers: api_headers, timeout: 15)

    if response.success?
      Rails.logger.info 'Evolution API: Instance deleted successfully'
    else
      Rails.logger.error "Evolution API delete error: #{response.code} - #{response.body}"
    end
  rescue StandardError => e
    Rails.logger.error "Evolution API delete exception: #{e.message}"
  end

  public :setup_channel_provider, :configure_webhook, :disconnect_channel_provider
end
