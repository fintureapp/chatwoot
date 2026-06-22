# frozen_string_literal: true

module CustomExceptions::Inbox
  class Disabled < CustomExceptions::Base
    def message
      'This inbox is currently disabled'
    end

    def error_code
      'inbox_disabled'
    end

    def http_status
      :forbidden
    end
  end
end
