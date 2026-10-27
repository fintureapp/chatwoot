/* global axios */
import ApiClient from './ApiClient';

// Home (Finture::HomeOverviewService). `filters`: inbox_id,
// purpose, team_id e period — os mesmos no resumo e na lista de cada indicador.
class FintureHomeApi extends ApiClient {
  constructor() {
    super('finture_home', { accountScoped: true });
  }

  get(filters) {
    return axios.get(this.url, { params: filters });
  }

  list(metric, filters) {
    return axios.get(`${this.url}/list`, { params: { ...filters, metric } });
  }
}

export default new FintureHomeApi();
