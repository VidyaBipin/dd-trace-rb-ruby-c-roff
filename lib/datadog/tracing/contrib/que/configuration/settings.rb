# frozen_string_literal: true

require_relative '../../../span_operation'
require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Que
        module Configuration
          # Default settings for the Que integration
          class Settings < Contrib::Configuration::Settings
            option :service_name
            option :distributed_tracing, default: true

            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            end

            option :tag_args do |o|
              o.default { env_to_bool(Ext::ENV_TAG_ARGS_ENABLED, false) }
            end

            option :tag_data do |o|
              o.default { env_to_bool(Ext::ENV_TAG_DATA_ENABLED, false) }
            end
            option :error_handler do |o|
              o.experimental_default_proc(&Tracing::SpanOperation::Events::DEFAULT_ON_ERROR)
            end
          end
        end
      end
    end
  end
end
