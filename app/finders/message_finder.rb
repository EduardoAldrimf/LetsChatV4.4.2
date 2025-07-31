class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    messages = current_messages
    include_contact_conversations? ? inject_conversation_separators(messages) : messages
  end

  private

  def conversation_messages
    scope = if include_contact_conversations?
              Message.joins(:conversation).where(conversation_id: contact_conversation_ids)
            else
              @conversation.messages
            end

    scope.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    messages.reorder(message_order(:asc)).where('messages.id > ?', after_id).limit(100)
  end

  def messages_before(before_id)
    messages.reorder(message_order(:desc)).where('messages.id < ?', before_id).limit(20).reverse
  end

  def messages_between(after_id, before_id)
    messages.reorder(message_order(:asc)).where('messages.id >= ? AND messages.id < ?', after_id, before_id).limit(1000)
  end

  def messages_latest
    messages.reorder(message_order(:desc)).limit(20).reverse
  end

  def message_order(direction)
    if include_contact_conversations?
      "conversations.created_at #{direction}, messages.created_at #{direction}"
    else
      "messages.created_at #{direction}"
    end
  end

  def include_contact_conversations?
    return false unless @conversation.account.feature_enabled?('conversation_history')

    flag = if @params.key?(:include_contact_conversations)
             @params[:include_contact_conversations]
           else
             contact_conversation_ids.length > 1
           end

    ActiveModel::Type::Boolean.new.cast(flag)
  end

  def contact_conversation_ids
    @conversation
      .contact
      .conversations
      .where(inbox_id: @conversation.inbox_id)
      .order(:created_at)
      .pluck(:id)
  end

  def inject_conversation_separators(messages)
    result = []
    current_id = nil
    messages.each do |msg|
      if current_id != msg.conversation_id
        result << ConversationSeparatorMessage.new(msg.conversation)
        current_id = msg.conversation_id
      end
      result << msg
    end
    result
  end
end
