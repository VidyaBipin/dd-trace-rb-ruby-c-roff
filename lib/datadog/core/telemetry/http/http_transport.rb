# typed: true

require 'datadog/core/configuration/settings'
require 'datadog/core/telemetry/http/env'
require 'datadog/core/telemetry/http/ext'
require 'datadog/core/telemetry/http/adapters/net'

module Datadog
  module Core
    module Telemetry
      module Http
        # Class to send telemetry data to Telemetry API
        class Transport
          attr_reader \
            :host,
            :port,
            :ssl,
            :path

          def initialize
            agent_settings = Datadog.configuration.agent

            @host = agent_settings.host
            @port = agent_settings.port
            @ssl = false
            @path = Http::Ext::AGENT_ENDPOINT
          end

          def request(request_type:, payload:)
            env = Http::Env.new
            env.path = @path
            env.body = payload
            env.headers = headers(request_type: request_type)
            adapter.post(env)
          end

          private

          def headers(request_type:, api_version: Http::Ext::API_VERSION)
            {
              Http::Ext::HEADER_CONTENT_TYPE => Http::Ext::CONTENT_TYPE_APPLICATION_JSON,
              Http::Ext::HEADER_DD_TELEMETRY_API_VERSION => api_version,
              Http::Ext::HEADER_DD_TELEMETRY_REQUEST_TYPE => request_type,
            }
          end

          def adapter
            @adapter ||= Http::Adapters::Net.new(hostname: @host, port: @port, ssl: @ssl)
          end
        end
      end
    end
  end
end
