/* global axios */
import ApiClient from '../ApiClient';

class CaptainAssistant extends ApiClient {
  constructor() {
    super('captain/assistants', { accountScoped: true });
  }

  get({ page = 1, searchKey } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        searchKey,
      },
    });
  }

  playground({ assistantId, messageContent, messageHistory }) {
    return axios.post(`${this.url}/${assistantId}/playground`, {
      message_content: messageContent,
      message_history: messageHistory,
    });
  }

  getStats({ assistantId, range }) {
    return axios.get(`${this.url}/${assistantId}/stats`, { params: { range } });
  }

  getSummary({ assistantId, range }) {
    return axios.get(`${this.url}/${assistantId}/summary`, {
      params: { range },
    });
  }
}

export default new CaptainAssistant();
