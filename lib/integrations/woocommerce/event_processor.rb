class Integrations::Woocommerce::EventProcessor
  pattr_initialize [:payload!, :event!, :resource!, :store!]

  def perform
    return if hook.blank?

    if event.to_s.start_with?('order.') || resource == 'order'
      process_order_event
    else
      Rails.logger.info "Unhandled WooCommerce event: #{resource} #{event}"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "WooCommerce webhook parse error: #{e.message}"
  end

  private

  def process_order_event
    data = JSON.parse(payload)
    contact = find_contact(data)
    return unless contact

    conversation = contact.conversations.last
    return unless conversation

    content = I18n.t(
      'conversations.activity.woocommerce.order_updated',
      order_id: data['id'],
      status: data['status']
    )

    Conversations::ActivityMessageJob.perform_later(
      conversation,
      {
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        message_type: :activity,
        content: content
      }
    )
  end

  def find_contact(data)
    email = data.dig('billing', 'email')
    phone = data.dig('billing', 'phone')

    contact = hook.account.contacts.from_email(email) if email.present?
    contact ||= hook.account.contacts.find_by(phone_number: phone) if phone.present?
    contact
  end

  def hook
    @hook ||= Integrations::Hook.find_by("settings ->> 'store_url' = ?", store.to_s.chomp('/'))
  end
end
