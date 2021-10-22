# typed: true
require 'ddtrace/utils/only_once'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  # A \Pin (a.k.a Patch INfo) is a small class which is used to
  # set tracing metadata on a particular traced object.
  # This is useful if you wanted to, say, trace two different
  # database clusters.
  class Pin
    def self.get_from(obj)
      return nil unless obj.respond_to? :datadog_pin

      obj.datadog_pin
    end

    attr_accessor :app, :app_type, :config, :name, :service, :tags, :writer

    def initialize(service, app: nil, app_type: nil, config: nil, tags: nil, **_kwargs)
      @service = service
      @app = app
      @app_type = app_type
      @config = config
      @tags = tags
      @name = nil # this would rarely be overridden as it's really span-specific
    end

    def tracer
      Datadog.tracer
    end

    def enabled?
      return tracer.enabled if tracer

      false
    end

    # rubocop:disable Style/TrivialAccessors
    def onto(obj)
      unless obj.respond_to? :datadog_pin=
        obj.instance_exec do
          def datadog_pin=(pin)
            @datadog_pin = pin
          end
        end
      end

      unless obj.respond_to? :datadog_pin
        obj.instance_exec do
          def datadog_pin
            @datadog_pin
          end
        end
      end

      obj.datadog_pin = self
    end

    def to_s
      "Pin(service:#{service},app:#{app},app_type:#{app_type},name:#{name})"
    end
  end
end
