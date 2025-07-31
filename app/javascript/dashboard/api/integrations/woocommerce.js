/* global axios */

import ApiClient from '../ApiClient';

class WooCommerceAPI extends ApiClient {
  constructor() {
    super('integrations/woocommerce', { accountScoped: true });
  }

  getOrders(contactId) {
    return axios.get(`${this.url}/orders`, {
      params: { contact_id: contactId },
    });
  }
}

export default new WooCommerceAPI();
