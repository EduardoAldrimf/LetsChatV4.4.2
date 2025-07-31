class Integrations::Woocommerce::Client
  pattr_initialize [:hook!]

  def configured?
    return false unless hook.settings.is_a?(Hash)

    store_url.present? && auth[:username].present? && auth[:password].present?
  end

  def orders(email, phone = nil)
    return [] if email.blank? && phone.blank?

    query_value = email.presence || phone

    response = HTTParty.get(
      "#{store_url}/wp-json/wc/v3/orders",
      basic_auth: auth,
      query: {
        search: query_value,
        consumer_key: auth[:username],
        consumer_secret: auth[:password]
      }
    )

    raise response.parsed_response.to_s unless response.success?

    response.parsed_response.map do |order|
      order.merge('admin_url' => "#{store_url}/wp-admin/post.php?post=#{order['id']}&action=edit")
    end
  end

  private

  def store_url
    return '' unless hook.settings.is_a?(Hash)

    hook.settings['store_url'].to_s.chomp('/')
  end

  def auth
    return { username: '', password: '' } unless hook.settings.is_a?(Hash)

    {
      username: hook.settings['consumer_key'].to_s,
      password: hook.settings['consumer_secret'].to_s
    }
  end
end
