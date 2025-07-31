class Api::V1::Accounts::Evolution::AuthorizationsController < Api::V1::Accounts::BaseController
  def create
    Rails.logger.info "Evolution API connection verification called with params: #{params.inspect}"

    # Parâmetros vêm dentro de authorization
    auth_params = params[:authorization] || params

    api_url = auth_params[:api_url].presence || ENV['EVOLUTION_API_URL']
    admin_token = auth_params[:admin_token].presence || ENV['EVOLUTION_ADMIN_TOKEN']
    instance_name = auth_params[:instance_name]
    phone_number = auth_params[:phone_number]

    if api_url.blank? || admin_token.blank? || instance_name.blank? || phone_number.blank?
      return render json: {
        error: 'Missing required parameters: api_url, admin_token, instance_name, phone_number'
      }, status: :bad_request
    end

    begin
      # First, check if Evolution API is running by hitting the root endpoint
      evolution_status = check_server_status(api_url)

      # Check if instance already exists, delete if it does
      check_and_delete_existing_instance(api_url, admin_token, instance_name)

      # Create new instance
      instance_data = create_instance(api_url, admin_token, instance_name, phone_number)

      # Get QR code for the new instance
      qrcode_data = get_qrcode(api_url, instance_data['hash'], instance_name)

      render json: {
        success: true,
        message: 'Instance created successfully',
        evolution_info: {
          version: evolution_status['version'],
          client_name: evolution_status['clientName'],
          whatsapp_version: evolution_status['whatsappWebVersion']
        },
        instance: instance_data,
        qrcode: qrcode_data
      }
    rescue StandardError => e
      Rails.logger.error "Evolution API connection error: #{e.message}"
      render json: {
        error: e.message
      }, status: :unprocessable_entity
    end
  end

  private

  def check_server_status(api_url)
    instance_url = "#{api_url.chomp('/')}/"
    Rails.logger.info "Evolution API: Checking server at #{instance_url}"

    uri = URI.parse(instance_url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request['Content-Type'] = 'application/json'

    Rails.logger.info "Evolution API: Request headers: #{request.to_hash}"

    response = http.request(request)
    Rails.logger.info "Evolution API: Server response code: #{response.code}"
    Rails.logger.info "Evolution API: Server response body: #{response.body}"

    raise "Server verification failed. Status: #{response.code}, Body: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error "Evolution API: Server JSON parse error: #{e.message}, Body: #{response&.body}"
    raise 'Invalid response from Evolution API server endpoint'
  rescue StandardError => e
    Rails.logger.error "Evolution API: Server connection error: #{e.class} - #{e.message}"
    raise "Failed to verify instance: #{e.message}"
  end

  def create_instance(api_url, admin_token, instance_name, phone_number)
    create_url = "#{api_url.chomp('/')}/instance/create"
    Rails.logger.info "Evolution API: Creating instance at #{create_url}"

    # Clean phone number (remove +, spaces, -)
    clean_number = phone_number.gsub(/[\+\s\-]/, '')

    # Get webhook URL (following Chatwoot pattern)
    webhook_url_value = webhook_url

    request_body = {
      instanceName: instance_name,
      number: clean_number,
      integration: 'WHATSAPP-BAILEYS',
      qrcode: false,
      webhook: {
        url: webhook_url_value,
        byEvents: false,
        base64: true,
        events: [
          # 'QRCODE_UPDATED',
          # 'MESSAGES_SET',
          'MESSAGES_UPSERT',
          'MESSAGES_UPDATE',
          'MESSAGES_DELETE',
          # 'SEND_MESSAGE',
          # 'CONTACTS_SET',
          # 'CONTACTS_UPSERT',
          'CONTACTS_UPDATE'
          # 'CONTACTS_DELETE',
          # 'CHATS_SET',
          # 'CHATS_UPSERT',
          # 'CHATS_UPDATE',
          # 'CHATS_DELETE',
          # 'GROUPS_UPSERT',
          # 'GROUP_UPDATE',
          # 'GROUP_PARTICIPANTS_UPDATE',
          # 'CONNECTION_UPDATE',
          # 'LABELS_EDIT',
          # 'LABELS_ASSOCIATION',
          # 'CALL'
        ]
      }
    }

    uri = URI.parse(create_url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 15
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri)
    request['apikey'] = admin_token
    request['Content-Type'] = 'application/json'
    request.body = request_body.to_json

    Rails.logger.info "Evolution API: Create instance request headers: #{request.to_hash}"
    Rails.logger.info "Evolution API: Create instance request body: #{request.body}"

    response = http.request(request)
    Rails.logger.info "Evolution API: Create instance response code: #{response.code}"
    Rails.logger.info "Evolution API: Create instance response body: #{response.body}"

    raise "Failed to create instance. Status: #{response.code}, Body: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error "Evolution API: Create instance JSON parse error: #{e.message}, Body: #{response&.body}"
    raise 'Invalid response from Evolution API create instance endpoint'
  rescue StandardError => e
    Rails.logger.error "Evolution API: Create instance connection error: #{e.class} - #{e.message}"
    raise "Failed to create instance: #{e.message}"
  end

  def check_and_delete_existing_instance(api_url, admin_token, instance_name)
    # Try to fetch existing instances

    fetch_instances(api_url, admin_token, instance_name)
    # If we get here, instance exists, so delete it
    Rails.logger.info "Evolution API: Instance #{instance_name} exists, deleting it"
    delete_instance(api_url, admin_token, instance_name)
    Rails.logger.info "Evolution API: Instance #{instance_name} deleted successfully"

    # Wait a bit for Evolution API to process the deletion
    Rails.logger.info 'Evolution API: Waiting 2 seconds for deletion to be processed...'
    sleep(2)

    # Verify the instance was actually deleted
    begin
      fetch_instances(api_url, admin_token, instance_name)
      # If we get here, instance still exists after deletion
      Rails.logger.error "Evolution API: Instance #{instance_name} still exists after deletion attempt"
      raise 'Instance deletion failed - instance still exists'
    rescue StandardError => e
      # If 404 or error, instance is gone - good!
      Rails.logger.info "Evolution API: Verified instance #{instance_name} was deleted (#{e.message})"
    end

  rescue StandardError => e
    # If 404 or any error, instance doesn't exist, which is fine
    Rails.logger.info "Evolution API: Instance #{instance_name} doesn't exist (#{e.message}), proceeding with creation"
  end

  def fetch_instances(api_url, admin_token, instance_name)
    fetch_url = "#{api_url.chomp('/')}/instance/fetchInstances?instanceName=#{instance_name}"
    Rails.logger.info "Evolution API: Fetching instances at #{fetch_url}"

    uri = URI.parse(fetch_url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request['apikey'] = admin_token
    request['Content-Type'] = 'application/json'

    response = http.request(request)
    Rails.logger.info "Evolution API: Fetch instances response code: #{response.code}"
    Rails.logger.info "Evolution API: Fetch instances response body: #{response.body}"

    # If 404, instance doesn't exist
    raise 'Instance not found' if response.code == '404'

    raise "Failed to fetch instances. Status: #{response.code}, Body: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error "Evolution API: Fetch instances JSON parse error: #{e.message}, Body: #{response&.body}"
    raise 'Invalid response from Evolution API fetchInstances endpoint'
  rescue StandardError => e
    Rails.logger.error "Evolution API: Fetch instances connection error: #{e.class} - #{e.message}"
    raise e.message
  end

  def delete_instance(api_url, admin_token, instance_name)
    delete_url = "#{api_url.chomp('/')}/instance/delete/#{instance_name}"
    Rails.logger.info "Evolution API: Deleting instance at #{delete_url}"

    uri = URI.parse(delete_url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 15
    http.read_timeout = 15

    request = Net::HTTP::Delete.new(uri)
    request['apikey'] = admin_token
    request['Content-Type'] = 'application/json'

    response = http.request(request)

    Rails.logger.info "Evolution API: Delete instance response code: #{response.code}"
    Rails.logger.info "Evolution API: Delete instance response body: #{response.body}"

    raise "Failed to delete instance. Status: #{response.code}, Body: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error "Evolution API: Delete instance JSON parse error: #{e.message}, Body: #{response&.body}"
    raise 'Invalid response from Evolution API delete endpoint'
  rescue StandardError => e
    Rails.logger.error "Evolution API: Delete instance connection error: #{e.class} - #{e.message}"
    raise "Failed to delete instance: #{e.message}"
  end

  def get_qrcode(api_url, api_hash, instance_name)
    qrcode_url = "#{api_url.chomp('/')}/instance/connect/#{instance_name}"
    Rails.logger.info "Evolution API: Getting QR code at #{qrcode_url}"

    uri = URI.parse(qrcode_url)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 15
    http.read_timeout = 15

    request = Net::HTTP::Get.new(uri)
    request['apikey'] = api_hash
    request['Content-Type'] = 'application/json'

    Rails.logger.info "Evolution API: QR code request headers: #{request.to_hash}"

    response = http.request(request)
    Rails.logger.info "Evolution API: QR code response code: #{response.code}"
    Rails.logger.info "Evolution API: QR code response body: #{response.body}"

    raise "Failed to get QR code. Status: #{response.code}, Body: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error "Evolution API: QR code JSON parse error: #{e.message}, Body: #{response&.body}"
    raise 'Invalid response from Evolution API QR code endpoint'
  rescue StandardError => e
    Rails.logger.error "Evolution API: QR code connection error: #{e.class} - #{e.message}"
    raise "Failed to get QR code: #{e.message}"
  end

  def webhook_url
    # Get the host from the current request
    host = request.host_with_port
    protocol = request.ssl? ? 'https' : 'http'

    # Follow the same pattern as Chatwoot WhatsApp webhook
    "#{protocol}://#{host}/webhooks/whatsapp"
  end
end
