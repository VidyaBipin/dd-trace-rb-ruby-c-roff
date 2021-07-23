# During development, we load `ddtrace` by through `ddtrace.gemspec`,
# which in turn eager loads 'ddtrace/version'.
#
# Users load this gem by requiring this file.
# We need to ensure that any files loaded in our gemspec are also loaded here.
require 'ddtrace/version'

require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'ddtrace/error'
require 'ddtrace/quantization/hash'
require 'ddtrace/quantization/http'
require 'ddtrace/pipeline'
require 'ddtrace/configuration'
require 'ddtrace/patcher'
require 'ddtrace/metrics'
require 'ddtrace/auto_instrument_base'
require 'ddtrace/profiling'

require 'ddtrace/contrib'
require 'ddtrace/contrib/auto_instrument'
require 'ddtrace/contrib/extensions'

require 'ddtrace/opentelemetry/extensions'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  extend Configuration
  extend AutoInstrumentBase

  # Load built-in Datadog integrations
  extend Contrib::Extensions
  # Load Contrib auto instrumentation
  extend Contrib::AutoInstrument
  # Load Contrib extension to global Datadog objects
  Configuration::Settings.include Contrib::Extensions::Configuration::Settings

  # Load and extend OpenTelemetry compatibility by default
  extend OpenTelemetry::Extensions

  # Add shutdown hook:
  # Ensures the tracer has an opportunity to flush traces
  # and cleanup before terminating the process.
  at_exit do
    if Interrupt === $! # rubocop:disable Style/SpecialGlobalVars is process terminating due to a ctrl+c or similar?
      Datadog.send(:handle_interrupt_shutdown!)
    else
      Datadog.shutdown!
    end
  end
end

require 'ddtrace/contrib/action_cable/integration'
require 'ddtrace/contrib/action_pack/integration'
require 'ddtrace/contrib/action_view/integration'
require 'ddtrace/contrib/active_model_serializers/integration'
require 'ddtrace/contrib/active_record/integration'
require 'ddtrace/contrib/active_support/integration'
require 'ddtrace/contrib/aws/integration'
require 'ddtrace/contrib/concurrent_ruby/integration'
require 'ddtrace/contrib/dalli/integration'
require 'ddtrace/contrib/delayed_job/integration'
require 'ddtrace/contrib/elasticsearch/integration'
require 'ddtrace/contrib/ethon/integration'
require 'ddtrace/contrib/excon/integration'
require 'ddtrace/contrib/faraday/integration'
require 'ddtrace/contrib/grape/integration'
require 'ddtrace/contrib/graphql/integration'
require 'ddtrace/contrib/grpc/integration'
require 'ddtrace/contrib/http/integration'
require 'ddtrace/contrib/httpclient/integration'
require 'ddtrace/contrib/httprb/integration'
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/kafka/integration'
require 'ddtrace/contrib/lograge/integration'
require 'ddtrace/contrib/presto/integration'
require 'ddtrace/contrib/que/integration'
require 'ddtrace/contrib/mysql2/integration'
require 'ddtrace/contrib/mongodb/integration'
require 'ddtrace/contrib/qless/integration'
require 'ddtrace/contrib/racecar/integration'
require 'ddtrace/contrib/rack/integration'
require 'ddtrace/contrib/rails/integration'
require 'ddtrace/contrib/rake/integration'
require 'ddtrace/contrib/redis/integration'
require 'ddtrace/contrib/resque/integration'
require 'ddtrace/contrib/rest_client/integration'
require 'ddtrace/contrib/semantic_logger/integration'
require 'ddtrace/contrib/sequel/integration'
require 'ddtrace/contrib/shoryuken/integration'
require 'ddtrace/contrib/sidekiq/integration'
require 'ddtrace/contrib/sinatra/integration'
require 'ddtrace/contrib/sneakers/integration'
require 'ddtrace/contrib/sucker_punch/integration'
