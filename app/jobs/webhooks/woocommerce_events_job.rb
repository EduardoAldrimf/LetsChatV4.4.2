class Webhooks::WoocommerceEventsJob < ApplicationJob
  queue_as :low

  def perform(payload:, event:, resource:, store:)
    Integrations::Woocommerce::EventProcessor.new(
      payload: payload,
      event: event,
      resource: resource,
      store: store
    ).perform
  end
end
