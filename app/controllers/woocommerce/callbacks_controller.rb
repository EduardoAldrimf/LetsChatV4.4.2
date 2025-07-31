class Woocommerce::CallbacksController < ActionController::API
  def create
    Webhooks::WoocommerceEventsJob.perform_later(
      payload: request.raw_post,
      event: request.headers['X-WC-Webhook-Event'],
      resource: request.headers['X-WC-Webhook-Resource'],
      store: request.headers['X-WC-Webhook-Source']
    )

    head :ok
  end
end
