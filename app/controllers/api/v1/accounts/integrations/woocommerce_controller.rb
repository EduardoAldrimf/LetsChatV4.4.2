class Api::V1::Accounts::Integrations::WoocommerceController < Api::V1::Accounts::BaseController
  before_action :fetch_hook, except: [:destroy]
  before_action :validate_contact, only: [:orders]

  def orders
    return render(json: { error: 'Integration not configured' }, status: :unprocessable_entity) unless @hook && woocommerce_client.configured?

    orders = woocommerce_client.orders(contact.email, contact.phone_number)
    render json: { orders: orders }
  rescue NoMethodError => e
    Rails.logger.error "WooCommerce integration error: #{e.message}"
    render json: { error: 'Integration configuration error' }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    fetch_hook
    @hook.destroy!
    head :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def contact
    @contact ||= Current.account.contacts.find_by(id: params[:contact_id])
  end

  def woocommerce_client
    Integrations::Woocommerce::Client.new(hook: @hook)
  end

  def fetch_hook
    @hook = Integrations::Hook.find_by(account: Current.account, app_id: 'woocommerce')
    return if @hook

    render json: { error: 'WooCommerce integration not found' }, status: :unprocessable_entity
    return
  end

  def validate_contact
    return unless contact.blank? || (contact.email.blank? && contact.phone_number.blank?)

    render json: { error: 'Contact information missing' }, status: :unprocessable_entity
  end
end
