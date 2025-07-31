class AddProviderConnectionToChannelWhatsapp < ActiveRecord::Migration[6.1]
  def change
    add_column :channel_whatsapp, :provider_connection, :jsonb, default: {}
  end
end
