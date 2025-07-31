class ConversationSeparatorMessage
  attr_reader :id, :content, :conversation, :message_type,
              :content_type, :status, :content_attributes,
              :created_at, :private, :sender, :inbox_id, :echo_id,
              :source_id

  def initialize(conversation)
    @conversation = conversation
    @id = "separator-#{conversation.id}"
    @content = I18n.t(
      'conversations.history.separator',
      id: conversation.display_id,
      date: conversation.created_at.strftime('%d %B %Y %H:%M')
    )
    @message_type = 'activity'
    @content_type = 'text'
    @status = 'sent'
    @content_attributes = {}
    @created_at = conversation.created_at
    @private = false
    @sender = nil
    @inbox_id = conversation.inbox_id
    @echo_id = nil
    @source_id = nil
  end

  def message_type_before_type_cast
    Message.message_types[@message_type]
  end

  def attachments
    []
  end
end
