module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  # Finture: a requisição se autenticou por token de API (api_access_token), não
  # pela sessão do painel. A Central de Demandas não credita autor nesses casos.
  thread_mattr_accessor :api_access_token_auth

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.api_access_token_auth = nil
  end
end
