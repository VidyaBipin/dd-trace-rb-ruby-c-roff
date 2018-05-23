require 'rails/all'
require 'ddtrace'

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'ddtrace/contrib/sidekiq/tracer'
end

require 'ddtrace/contrib/rails/support/controllers'
require 'ddtrace/contrib/rails/support/middleware'
require 'ddtrace/contrib/rails/support/models'

RSpec.shared_context 'Rails 4 base application' do
  include_context 'Rails controllers'
  include_context 'Rails middleware'
  include_context 'Rails models'

  let(:rails_base_application) do
    reset_rails_configuration!
    klass = Class.new(Rails::Application) do
      def config.database_configuration
        parsed = super
        raise parsed.to_yaml # Replace this line to add custom connections to the hash from database.yml
      end
    end
    during_init = initialize_block

    klass.send(:define_method, :initialize) do |*args|
      super(*args)
      redis_cache = [:redis_store, { url: ENV['REDIS_URL'] }]
      file_cache = [:file_store, '/tmp/ddtrace-rb/cache/']

      config.secret_key_base = 'f624861242e4ccf20eacb6bb48a886da'
      config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
      config.eager_load = false
      config.consider_all_requests_local = true
      config.active_support.test_order = :random
      config.middleware.delete ActionDispatch::DebugExceptions
      instance_eval(&during_init)

      if ENV['USE_SIDEKIQ']
        config.active_job.queue_adapter = :sidekiq
        # add Sidekiq middleware
        Sidekiq::Testing.server_middleware do |chain|
          chain.add(
            Datadog::Contrib::Sidekiq::Tracer
          )
        end
      end
    end

    before_test_init = before_test_initialize_block
    after_test_init = after_test_initialize_block

    klass.send(:define_method, :test_initialize!) do
      # Enables the auto-instrumentation for the testing application
      Datadog.configure do |c|
        c.use :rails
        c.use :redis
      end

      Rails.application.config.active_job.queue_adapter = :sidekiq

      before_test_init.call
      initialize!
      after_test_init.call
    end
  end

  def append_routes!
    # Make sure to load controllers first
    # otherwise routes won't draw properly.
    controllers
    delegate = method(:draw_test_routes!)

    # Then set the routes
    if Rails.version >= '3.2.22.5'
      rails_test_application.instance.routes.append do
        delegate.call(self)
      end
    else
      rails_test_application.instance.routes.draw do
        delegate.call(self)
      end
    end
  end

  def draw_test_routes!(mapper)
    # Rails 4 accumulates these route drawing
    # blocks errantly, and this prevents them from
    # drawing more than once.
    return if @drawn

    test_routes = routes
    mapper.instance_exec do
      test_routes.each do |k, v|
        get k => v
      end
    end
    @drawn = true
  end

  # Rails 4 leaves a bunch of global class configuration on Rails::Railtie::Configuration in class variables
  # We need to reset these so they don't carry over between example runs
  def reset_rails_configuration!
    Rails::Railtie::Configuration.class_variable_set(:@@eager_load_namespaces, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_files, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@watchable_dirs, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@app_middleware, app_middleware)
    Rails::Railtie::Configuration.class_variable_set(:@@app_generators, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@to_prepare_blocks, nil)
  end

  def app_middleware
    current = Rails::Railtie::Configuration.class_variable_get(:@@app_middleware)
    Datadog::Contrib::Rails::Test::Configuration.fetch(:app_middleware, current).dup.tap do |copy|
      copy.instance_variable_set(:@operations, (copy.instance_variable_get(:@operations) || []).dup)
      copy.instance_variable_set(:@delete_operations, (copy.instance_variable_get(:@delete_operations) || []).dup)
    end
  end
end
