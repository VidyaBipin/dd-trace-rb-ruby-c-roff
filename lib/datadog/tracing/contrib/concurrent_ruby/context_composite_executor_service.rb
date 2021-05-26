# frozen_string_literal: true

require 'concurrent/executor/executor_service'

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # Wraps existing executor to carry over trace context
        class ContextCompositeExecutorService
          include Concurrent::ExecutorService

          attr_accessor :composited_executor

          def initialize(composited_executor)
            @composited_executor = composited_executor
          end

          # post method runs the task within composited executor - in a different thread. The original arguments are
          # captured to be propagated to the composited executor post method
          def post(*args, &task)
            tracer = Tracing.send(:tracer)
            parent_context = tracer.provider.context
            executor = @composited_executor.is_a?(Symbol) ? Concurrent.executor(@composited_executor) : @composited_executor

            # Pass the original arguments to the composited executor, which
            # pushes them (possibly transformed) as block args
            executor.post(*args) do |*block_args|
              begin
                original_context = tracer.provider.context
                tracer.provider.context = parent_context

                # Pass the executor-provided block args as they should have been
                # originally passed without composition, see ChainPromise#on_resolvable
                yield(*block_args)
              ensure
                # Restore context in case the current thread gets reused
                tracer.provider.context = original_context
              end
            end
          end

          # Respect the {Concurrent::ExecutorService} interface
          def can_overflow?
            @composited_executor.can_overflow?
          end

          # Respect the {Concurrent::ExecutorService} interface
          def serialized?
            @composited_executor.serialized?
          end

          def datadog_configuration
            Datadog.configuration.tracing[:concurrent_ruby]
          end
        end
      end
    end
  end
end
