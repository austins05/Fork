const axios = require('axios');
const config = require('../config/tabula');

class TabulaService {
  constructor() {
    this.client = axios.create({
      baseURL: config.apiUrl,
      timeout: config.timeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    });

    // Add request interceptor for authentication
    this.client.interceptors.request.use(
      (config) => {
        if (this.apiKey && this.apiSecret) {
          // TODO: Add authentication headers based on Tabula API requirements
          // This will be updated once we have the actual API credentials and documentation
          config.headers['Authorization'] = `Bearer ${this.apiKey}`;
          // Or it might be: config.headers['X-API-Key'] = this.apiKey;
        }
        return config;
      },
      (error) => Promise.reject(error)
    );
  }

  /**
   * Search for customers by name or other criteria
   * @param {string} searchQuery - Search term
   * @param {number} limit - Maximum number of results
   * @returns {Promise<Array>} List of customers
   */
  async searchCustomers(searchQuery, limit = 50) {
    try {
      // TODO: Update endpoint once we have actual Tabula API documentation
      const response = await this.client.get('/customers/search', {
        params: {
          q: searchQuery,
          limit: limit
        }
      });

      return response.data;
    } catch (error) {
      console.error('Error searching customers:', error.message);
      throw this.handleError(error);
    }
  }

  /**
   * Get customer details by ID
   * @param {string} customerId - Customer ID
   * @returns {Promise<Object>} Customer details
   */
  async getCustomer(customerId) {
    try {
      const response = await this.client.get(`/customers/${customerId}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching customer:', error.message);
      throw this.handleError(error);
    }
  }

  /**
   * Get field maps for a customer
   * @param {string} customerId - Customer ID
   * @returns {Promise<Array>} List of field maps
   */
  async getFieldMaps(customerId) {
    try {
      const response = await this.client.get(`/customers/${customerId}/fields`);
      return response.data;
    } catch (error) {
      console.error('Error fetching field maps:', error.message);
      throw this.handleError(error);
    }
  }

  /**
   * Get field maps for multiple customers
   * @param {Array<string>} customerIds - Array of customer IDs
   * @returns {Promise<Array>} Combined list of field maps
   */
  async getFieldMapsForMultipleCustomers(customerIds) {
    try {
      const promises = customerIds.map(id => this.getFieldMaps(id));
      const results = await Promise.allSettled(promises);

      // Combine successful results and log failures
      const fieldMaps = [];
      results.forEach((result, index) => {
        if (result.status === 'fulfilled') {
          fieldMaps.push(...result.value);
        } else {
          console.error(`Failed to fetch field maps for customer ${customerIds[index]}:`, result.reason);
        }
      });

      return fieldMaps;
    } catch (error) {
      console.error('Error fetching multiple field maps:', error.message);
      throw this.handleError(error);
    }
  }

  /**
   * Get detailed field map data including boundaries and metadata
   * @param {string} fieldId - Field/map ID
   * @returns {Promise<Object>} Detailed field map data
   */
  async getFieldMapDetails(fieldId) {
    try {
      const response = await this.client.get(`/fields/${fieldId}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching field map details:', error.message);
      throw this.handleError(error);
    }
  }

  /**
   * Download field map as GeoJSON or other format
   * @param {string} fieldId - Field/map ID
   * @param {string} format - Export format (geojson, kml, etc.)
   * @returns {Promise<Object>} Field map data in requested format
   */
  async downloadFieldMap(fieldId, format = 'geojson') {
    try {
      const response = await this.client.get(`/fields/${fieldId}/export`, {
        params: { format }
      });
      return response.data;
    } catch (error) {
      console.error('Error downloading field map:', error.message);
      throw this.handleError(error);
    }
  }

  /**
   * Handle API errors and provide meaningful messages
   * @param {Error} error - Original error
   * @returns {Error} Formatted error
   */
  handleError(error) {
    if (error.response) {
      // Server responded with error status
      return new Error(
        `Tabula API Error (${error.response.status}): ${
          error.response.data.message || error.response.statusText
        }`
      );
    } else if (error.request) {
      // Request was made but no response received
      return new Error('Tabula API Error: No response from server');
    } else {
      // Something else happened
      return new Error(`Tabula API Error: ${error.message}`);
    }
  }
}

module.exports = new TabulaService();
