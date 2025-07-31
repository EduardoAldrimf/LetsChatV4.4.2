/* global axios */

class EvolutionAPI {
  static async logout(apiUrl, adminToken, instanceName) {
    if (!apiUrl || !adminToken || !instanceName) {
      return Promise.reject(new Error('Missing Evolution credentials'));
    }
    const url = `${apiUrl.replace(/\/$/, '')}/instance/logout/${instanceName}`;

    try {
      const response = await axios.delete(url, {
        headers: {
          apikey: adminToken,
          'Content-Type': 'application/json',
        },
      });

      return response.data;
    } catch (error) {
      if (error.response) {
        throw new Error(error.response.data.message || 'Logout failed');
      }
      throw new Error('Network error during logout');
    }
  }

  static async fetchInstances(apiUrl, adminToken) {
    if (!apiUrl || !adminToken) {
      return Promise.reject(new Error('Missing Evolution credentials'));
    }
    const url = `${apiUrl.replace(/\/$/, '')}/instance/fetchInstances`;

    try {
      const response = await axios.get(url, {
        headers: {
          apikey: adminToken,
          'Content-Type': 'application/json',
        },
      });

      return response.data;
    } catch (error) {
      if (error.response) {
        throw new Error(
          error.response.data.message || 'Failed to fetch instances'
        );
      }
      throw new Error('Network error while fetching instances');
    }
  }

  static async getQRCode(apiUrl, adminToken, instanceName) {
    if (!apiUrl || !adminToken || !instanceName) {
      return Promise.reject(new Error('Missing Evolution credentials'));
    }
    const url = `${apiUrl.replace(/\/$/, '')}/instance/connect/${instanceName}`;

    try {
      const response = await axios.get(url, {
        headers: {
          apikey: adminToken,
          'Content-Type': 'application/json',
        },
      });

      return response.data;
    } catch (error) {
      if (error.response) {
        throw new Error(error.response.data.message || 'Failed to get QR code');
      }
      throw new Error('Network error while getting QR code');
    }
  }

  static async findSettings(apiUrl, adminToken, instanceName) {
    if (!apiUrl || !adminToken || !instanceName) {
      return Promise.reject(new Error('Missing Evolution credentials'));
    }
    const url = `${apiUrl.replace(/\/$/, '')}/settings/find/${instanceName}`;

    try {
      const response = await axios.get(url, {
        headers: {
          apikey: adminToken,
          'Content-Type': 'application/json',
        },
      });

      return response.data;
    } catch (error) {
      if (error.response) {
        throw new Error(
          error.response.data.message || 'Failed to fetch settings'
        );
      }
      throw new Error('Network error while fetching settings');
    }
  }

  static async setSettings(apiUrl, adminToken, instanceName, settings) {
    if (!apiUrl || !adminToken || !instanceName) {
      return Promise.reject(new Error('Missing Evolution credentials'));
    }
    const url = `${apiUrl.replace(/\/$/, '')}/settings/set/${instanceName}`;

    try {
      const response = await axios.post(url, settings, {
        headers: {
          apikey: adminToken,
          'Content-Type': 'application/json',
        },
      });

      return response.data;
    } catch (error) {
      if (error.response) {
        throw new Error(
          error.response.data.message || 'Failed to update settings'
        );
      }
      throw new Error('Network error while updating settings');
    }
  }
}

export default EvolutionAPI;
