/* global axios */
import ApiClient from './ApiClient';

class EvolutionAPI extends ApiClient {
  constructor() {
    super('evolution', { accountScoped: true });
  }

  verifyConnection({ apiUrl, adminToken, instanceName, phoneNumber }) {
    const requestData = {
      api_url: apiUrl,
      admin_token: adminToken,
      instance_name: instanceName,
      phone_number: phoneNumber,
    };
    return axios.post(`${this.url}/authorization`, requestData);
  }

  refreshQrCode({ apiUrl, apiHash, instanceName }) {
    const requestData = {
      api_url: apiUrl,
      api_hash: apiHash,
      instance_name: instanceName,
    };
    return axios.post(`${this.url}/qrcode`, requestData);
  }

  setProxy({ apiUrl, apiHash, instanceName, proxySettings }) {
    const requestData = {
      api_url: apiUrl,
      api_hash: apiHash,
      instance_name: instanceName,
      proxy_settings: proxySettings,
    };
    return axios.post(`${this.url}/proxy`, requestData);
  }

  setSettings({ apiUrl, apiHash, instanceName, instanceSettings }) {
    const requestData = {
      api_url: apiUrl,
      api_hash: apiHash,
      instance_name: instanceName,
      instance_settings: instanceSettings,
    };
    return axios.post(`${this.url}/settings`, requestData);
  }
}

export default new EvolutionAPI();
