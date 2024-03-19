require_relative '../../../core/utils/only_once'
require_relative '../rack/middlewares'
require_relative 'framework'
require_relative 'log_injection'
require_relative 'middlewares'
require_relative 'utils'
require_relative '../semantic_logger/patcher'
require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module Rails
        # Patcher to begin span on Rails routing
        module RoutingRouteSetPatch
          def call(*args, **kwargs)
            result = nil

            configuration = Datadog.configuration.tracing[:rails]

            Tracing.trace(
              Ext::SPAN_ROUTE,
              service: configuration[:service_name],
              span_type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND,
            ) do |span|
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_ROUTING)
              result = super
            end

            result
          end
        end

        # Patcher to trace rails routing done by JourneyRouter
        module JourneyRouterPatch
          def find_routes(*args, **kwargs)
            result = super

            if Datadog::Tracing.enabled? && (span = Datadog::Tracing.active_span)
              if result.any?
                datadog_route = result.first[2].path.spec.to_s
              end

              # TODO: instead of a thread local this may be put in env[something], but I'm not sure we can rely on it bubbling all the way up. see https://github.com/rack/rack/issues/2144
              # TODO: :rails should be a reference to the integration name
              Thread.current[:datadog_http_routing] << [:rails, args.first.env['SCRIPT_NAME'], args.first.env['PATH_INFO'], datadog_route]

              span.resource = datadog_route.to_s

              # TODO: should this rather be like this?
              # span.set_tag(Ext::TAG_ROUTE_PATH, path_info)
              # span.set_tag(Ext::TAG_ROUTE_PATTERN, datadog_path)
              span.set_tag(Ext::TAG_ROUTE_PATH, datadog_route)
            end

            result
          end
        end

        # Patcher enables patching of 'rails' module.
        module Patcher
          include Contrib::Patcher

          BEFORE_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Core::Utils::OnlyOnce.new }
          AFTER_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Core::Utils::OnlyOnce.new }

          module_function

          def target_version
            Integration.version
          end

          def patch
            patch_before_initialize
            patch_after_initialize
          end

          def patch_before_initialize
            ::ActiveSupport.on_load(:before_initialize) do
              Contrib::Rails::Patcher.before_initialize(self)
            end
          end

          def before_initialize(app)
            BEFORE_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Middleware must be added before the application is initialized.
              # Otherwise the middleware stack will be frozen.
              # Sometimes we don't want to activate middleware e.g. OpenTracing, etc.
              add_middleware(app) if Datadog.configuration.tracing[:rails][:middleware]

              ActionDispatch::Routing::RouteSet.prepend(RoutingRouteSetPatch)
              ActionDispatch::Journey::Router.prepend(JourneyRouterPatch)

              Rails::LogInjection.configure_log_tags(app.config)
            end
          end

          def add_middleware(app)
            # Add trace middleware at the top of the middleware stack,
            # to ensure we capture the complete execution time.
            app.middleware.insert_before(0, Contrib::Rack::TraceMiddleware)

            # Some Rails middleware can swallow an application error, preventing
            # the error propagation to the encompassing Rack span.
            #
            # We insert our own middleware right before these Rails middleware
            # have a chance to swallow the error.
            #
            # Note: because the middleware stack is push/pop, "before" and "after" are reversed
            # for our use case: we insert ourselves with "after" a middleware to ensure we are
            # able to pop the request "before" it.
            app.middleware.insert_after(::ActionDispatch::DebugExceptions, Contrib::Rails::ExceptionMiddleware)
          end

          def patch_after_initialize
            ::ActiveSupport.on_load(:after_initialize) do
              Contrib::Rails::Patcher.after_initialize(self)
            end
          end

          def after_initialize(app)
            AFTER_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Finish configuring the tracer after the application is initialized.
              # We need to wait for some things, like application name, middleware stack, etc.
              setup_tracer
            end
          end

          # Configure Rails tracing with settings
          def setup_tracer
            Contrib::Rails::Framework.setup
          end
        end
      end
    end
  end
end
