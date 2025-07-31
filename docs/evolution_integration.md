# WhatsApp Evolution Channel Integration

This project includes a provider for the Evolution API. Configuration values such as API URL, keys, or instance identifiers are stored in the `provider_config` JSONB column on `channel_whatsapp`.

## Required Environment Variables

```
EVOLUTION_API_URL=http://localhost:8080
EVOLUTION_ADMIN_TOKEN=your_admin_token_here
EVOLUTION_API_TIMEOUT=30
```

## Database Changes

Use the migration below to add a `provider_connection` field used to store connection information returned by the Evolution API.

```ruby
class AddProviderConnectionToChannelWhatsapp < ActiveRecord::Migration[6.1]
  def change
    add_column :channel_whatsapp, :provider_connection, :jsonb, default: {}
  end
end
```

After running `rails db:migrate`, `Channel::Whatsapp` will be able to persist Evolution connection details.

When setting up a new WhatsApp inbox you can call `Api::V1::Accounts::Evolution::AuthorizationsController#create` to verify the Evolution API connection and create an instance. This returns the QR code required to pair the WhatsApp device.

Behind the scenes the controller posts to `/instance/create` using the inbox phone number and sets the webhook to `FRONTEND_URL/webhooks/whatsapp/:phone_number`. Evolution will then deliver `messages.upsert` and `messages.update` events back to Chatwoot.

## Conversation Flow

Evolution does not require using WhatsApp templates to initiate conversations. If a contact has not messaged recently you can still send regular text messages through the Evolution provider.
