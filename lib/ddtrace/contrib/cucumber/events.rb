require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/cucumber/ext'

module Datadog
  module Contrib
    module Cucumber
      # Defines collection of instrumented Cucumber events
      class Events
        attr_reader :config, :pin
        private :config, :pin

        attr_reader :current_feature_span, :current_step_span
        private :current_feature_span, :current_step_span

        def initialize(config)
          @config = config
          @pin = Datadog::Pin.new(
            Datadog.configuration[:cucumber][:service_name],
            app: Datadog::Contrib::Cucumber::Ext::APP,
            app_type: Datadog::Ext::AppTypes::TEST,
            tracer: -> { Datadog.configuration[:cucumber][:tracer] }
          )

          bind_events(config)
        end

        def bind_events(config)
          config.on_event :test_case_started, &method(:on_test_case_started)
          config.on_event :test_case_finished, &method(:on_test_case_finished)
          config.on_event :test_step_started, &method(:on_test_step_started)
          config.on_event :test_step_finished, &method(:on_test_step_finished)
        end

        def on_test_case_started(event)
          trace_options = { resource: event.test_case.name, span_type: Datadog::Contrib::Cucumber::Ext::STEP_SPAN_TYPE }
          @current_feature_span = @pin.tracer.trace(Datadog::Ext::AppTypes.TEST, trace_options)
        end

        def on_test_case_finished(event)
          return if @current_feature_span.nil?
          @current_feature_span.status = 1 if event.result.failed?
          @current_feature_span.finish
        end

        def on_test_step_started(event)
          trace_options = { resource: event.test_step.to_s, span_type: 'step' }
          @current_step_span = @pin.tracer.trace('step', trace_options)
        end

        def on_test_step_finished(event)
          return if @current_step_span.nil?
          @current_span = pin.tracer.active_span
          unless step.result.passed?
            @current_step_span.set_error event.result.exception
          end
          @current_step_span.finish
        end
      end
    end
  end
end
