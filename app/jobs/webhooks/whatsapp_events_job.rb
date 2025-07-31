class Webhooks::WhatsappEventsJob < ApplicationJob
  queue_as :low

  def perform(params = {})
    Rails.logger.info "WhatsApp webhook processing started: #{params.inspect}"

    channel = find_channel(params)
    if channel_is_inactive?(channel)
      Rails.logger.warn("Inactive WhatsApp channel: #{channel&.phone_number || "unknown - #{params[:phone_number]}"}")
      return
    end

    Rails.logger.info "Found WhatsApp channel: #{channel.phone_number} (provider: #{channel.provider})"

    case channel.provider
    when 'whatsapp_cloud'
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
    when 'baileys'
      Whatsapp::IncomingMessageBaileysService.new(inbox: channel.inbox, params: params).perform
    when 'evolution'
      Whatsapp::IncomingMessageEvolutionService.new(inbox: channel.inbox, params: params).perform
    else
      Whatsapp::IncomingMessageService.new(inbox: channel.inbox, params: params).perform
    end
  end

  private

  def find_channel(params)
    # Log detailed params for debugging
    Rails.logger.info "WhatsApp webhook channel search started with params: #{params.slice(:event, :instance, :phone_number, :server_url, :object)}"

    channel = try_find_channel_from_business_payload(params) ||
              try_find_channel_by_phone_number_id(params) ||
              try_find_channel_by_phone_number(params)

    log_channel_search_result(channel, params)
    channel
  end

  def try_find_channel_from_business_payload(params)
    return nil unless params[:object] == 'whatsapp_business_account'

    channel = find_channel_from_whatsapp_business_payload(params)
    Rails.logger.info "Channel search via Business payload: #{channel ? "found #{channel.phone_number}" : 'not found'}"
    channel
  end

  def try_find_channel_by_phone_number_id(params)
    phone_number_id = extract_phone_number_id_from_params(params)
    return nil if phone_number_id.blank?

    channel = find_channel_by_phone_number_id(phone_number_id)
    Rails.logger.info "Channel search via phone_number_id #{phone_number_id}: #{channel ? "found #{channel.phone_number}" : 'not found'}"
    channel
  end

  def try_find_channel_by_phone_number(params)
    # For Evolution API, prioritize finding by instance name + server_url
    if params[:instance].present? && params[:event].present?
      channel = find_channel_by_evolution_instance(params[:instance], params[:server_url])
      if channel
        Rails.logger.info "Channel search via Evolution instance #{params[:instance]}: found #{channel.phone_number}"
        return channel
      end
    end

    # Try phone_number parameter for other providers
    if params[:phone_number].present?
      channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
      if channel
        Rails.logger.info "Channel search via phone_number #{params[:phone_number]}: found #{channel.phone_number}"
        return channel
      end
    end

    Rails.logger.info "Channel search: no channel found for params #{params.slice(:phone_number, :instance, :event)}"
    nil
  end

  def find_channel_by_phone_number_id(phone_number_id)
    Channel::Whatsapp.joins(:inbox)
                     .where(provider: 'whatsapp_cloud')
                     .where("provider_config ->> 'phone_number_id' = ?", phone_number_id.to_s)
                     .first
  end

  def find_channel_by_evolution_instance(instance_name, server_url = nil)
    # Try to find by both instance_name and server_url for better precision
    if server_url.present?
      channel = Channel::Whatsapp.joins(:inbox)
                                 .where(provider: 'evolution')
                                 .where("provider_config ->> 'instance_name' = ?", instance_name)
                                 .where("provider_config ->> 'api_url' = ?", server_url)
                                 .first

      Rails.logger.info "Evolution channel search: instance=#{instance_name}, server_url=#{server_url} - #{channel ? 'found' : 'not found'}"
      return channel if channel
    end

    # Fallback to instance_name only if server_url matching fails
    channel = Channel::Whatsapp.joins(:inbox)
                               .where(provider: 'evolution')
                               .where("provider_config ->> 'instance_name' = ?", instance_name)
                               .first

    Rails.logger.info "Evolution channel search (fallback): instance=#{instance_name} only - #{channel ? 'found' : 'not found'}"
    channel
  end

  def log_channel_search_result(channel, params)
    if channel
      Rails.logger.info "✅ Channel found: #{channel.phone_number} (provider: #{channel.provider}, inbox: #{channel.inbox.name})"
    else
      Rails.logger.warn "❌ No channel found for webhook params: #{params.slice(:event, :instance, :phone_number, :server_url, :object)}"

      # Additional debugging for Evolution API
      if params[:instance].present?
        evolution_channels = Channel::Whatsapp.where(provider: 'evolution')
        Rails.logger.warn "Available Evolution channels: #{evolution_channels.map do |c|
          "#{c.phone_number} (instance: #{c.provider_config['instance_name']}, api_url: #{c.provider_config['api_url']})"
        end}"
      end
    end
  end

  def channel_is_inactive?(channel)
    return true if channel.blank?
    return true if channel.reauthorization_required?
    return true unless channel.account.active?

    false
  end

  def find_channel_from_whatsapp_business_payload(params)
    phone_number, phone_number_id = extract_business_payload_metadata(params)

    Rails.logger.info "Business payload metadata: phone_number=#{phone_number}, phone_number_id=#{phone_number_id}"

    # First try to find by phone_number and validate phone_number_id
    channel = find_and_validate_channel_by_phone(phone_number, phone_number_id)
    return channel if channel

    # If no match by phone_number, try to find by phone_number_id only
    find_channel_by_phone_number_id_only(phone_number_id)
  end

  def extract_business_payload_metadata(params)
    metadata = params[:entry]&.first&.dig(:changes)&.first&.dig(:value, :metadata)
    return [nil, nil] unless metadata

    phone_number = "+#{metadata[:display_phone_number]}"
    phone_number_id = metadata[:phone_number_id]

    [phone_number, phone_number_id]
  end

  def find_and_validate_channel_by_phone(phone_number, phone_number_id)
    channel = Channel::Whatsapp.find_by(phone_number: phone_number)

    if channel&.provider_config&.dig('phone_number_id') == phone_number_id
      Rails.logger.info 'Channel matched by phone_number and phone_number_id validation'
      return channel
    end

    nil
  end

  def find_channel_by_phone_number_id_only(phone_number_id)
    return nil if phone_number_id.blank?

    channel = find_channel_by_phone_number_id(phone_number_id)
    Rails.logger.info "Channel search by phone_number_id only: #{channel ? "found #{channel.phone_number}" : 'not found'}"
    channel
  end

  def extract_phone_number_id_from_params(params)
    phone_number_id = extract_from_entry_changes(params) ||
                      extract_from_metadata(params) ||
                      extract_from_messages(params)

    Rails.logger.info "Extracted phone_number_id: #{phone_number_id}" if phone_number_id.present?
    phone_number_id
  end

  def extract_from_entry_changes(params)
    return nil if params[:entry].blank?

    params[:entry].first[:changes]&.first&.dig(:value, :metadata, :phone_number_id)
  end

  def extract_from_metadata(params)
    return nil if params[:metadata].blank?

    params[:metadata][:phone_number_id]
  end

  def extract_from_messages(params)
    return nil if params[:messages].blank?

    params[:messages].first&.dig(:metadata, :phone_number_id)
  end
end
