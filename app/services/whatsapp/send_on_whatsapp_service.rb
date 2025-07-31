class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    if channel.provider == 'evolution'
      template_params.present? ? send_template_message : send_session_message
      return
    end

    should_send_template_message = template_params.present? || !message.conversation.can_reply?
    if should_send_template_message
      send_template_message
    else
      send_session_message
    end
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    return if name.blank?

    message_id = channel.send_template(message.conversation.contact_inbox.source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       })
    if message_id.present?
      message.update!(source_id: message_id)
    else
      Messages::StatusUpdateService.new(message, 'failed', 'Evolution API error').perform
    end
  end

  def send_session_message
    message_id = channel.send_message(message.conversation.contact_inbox.source_id, message)
    if message_id.present?
      message.update!(source_id: message_id)
    else
      Messages::StatusUpdateService.new(message, 'failed', 'Evolution API error').perform
    end
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
