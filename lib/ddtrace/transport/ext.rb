# frozen_string_literal: true

require_relative '../../datadog/core/configuration/ext'

module Datadog
  module Transport
    # @public_api
    module Ext
      # @public_api
      module HTTP
        ADAPTER = Datadog::Core::Configuration::Ext::Transport::HTTP::ADAPTER
        DEFAULT_HOST = Datadog::Core::Configuration::Ext::Transport::HTTP::DEFAULT_HOST
        DEFAULT_PORT = Datadog::Core::Configuration::Ext::Transport::HTTP::DEFAULT_PORT

        HEADER_CONTAINER_ID = 'Datadog-Container-ID'
        HEADER_DD_API_KEY = 'DD-API-KEY'
        # Tells agent that `_dd.top_level` metrics have been set by the tracer.
        # The agent will not calculate top-level spans but instead trust the tracer tagging.
        #
        # This prevents partially flushed traces being mistakenly marked as top-level.
        #
        # Setting this header to any non-empty value enables this feature.
        HEADER_CLIENT_COMPUTED_TOP_LEVEL = 'Datadog-Client-Computed-Top-Level'
        HEADER_META_LANG = 'Datadog-Meta-Lang'
        HEADER_META_LANG_VERSION = 'Datadog-Meta-Lang-Version'
        HEADER_META_LANG_INTERPRETER = 'Datadog-Meta-Lang-Interpreter'
        HEADER_META_TRACER_VERSION = 'Datadog-Meta-Tracer-Version'

        # Header that prevents the Net::HTTP integration from tracing internal trace requests.
        # Set it to any value to skip tracing.
        HEADER_DD_INTERNAL_UNTRACED_REQUEST = 'DD-Internal-Untraced-Request'
      end

      # @public_api
      module Test
        ADAPTER = :test
      end

      # @public_api
      module UnixSocket
        ADAPTER = Datadog::Core::Configuration::Ext::Transport::UnixSocket::ADAPTER
        DEFAULT_PATH = Datadog::Core::Configuration::Ext::Transport::UnixSocket::DEFAULT_PATH
        DEFAULT_TIMEOUT_SECONDS = Datadog::Core::Configuration::Ext::Transport::UnixSocket::DEFAULT_TIMEOUT_SECONDS
      end
    end
  end
end
