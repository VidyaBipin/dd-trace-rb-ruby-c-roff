# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      module Ext
        ENV_ENABLED = 'DD_INSTRUMENTATION_TELEMETRY_ENABLED'
        ENV_HEARTBEAT_INTERVAL = 'DD_TELEMETRY_HEARTBEAT_INTERVAL'
        ENV_DEPENDENCY_COLLECTION = 'DD_TELEMETRY_DEPENDENCY_COLLECTION_ENABLED'
        ENV_INSTALL_ID = 'DD_INSTRUMENTATION_INSTALL_ID'
        ENV_INSTALL_TYPE = 'DD_INSTRUMENTATION_INSTALL_TYPE'
        ENV_INSTALL_TIME = 'DD_INSTRUMENTATION_INSTALL_TIME'
      end
    end
  end
end
