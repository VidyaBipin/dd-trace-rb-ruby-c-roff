# typed: ignore
# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Rack integration constants
        module Ext
          APP = 'rack'
          ENV_ENABLED = 'DD_TRACE_RACK_ENABLED' # TODO: DD_APPSEC?

          RESPONSE_STATUS = 'response.status'
          RESQUEST_BODY = 'request.body'
          REQUEST_HEADERS = 'request.headers'
          REQUEST_URI_RAW = 'request.uri.raw'
          REQUEST_QUERY = 'request.query'
          REQUEST_COOKIES = 'request.cookies'
          REQUEST_CLIENT_IP = 'request.client_ip'

          RACK_REQUEST = 'rack.request'
          RACK_REQUEST_BODY = 'rack.request.body'
          RACK_RESPONSE = 'rack.response'
        end
      end
    end
  end
end
