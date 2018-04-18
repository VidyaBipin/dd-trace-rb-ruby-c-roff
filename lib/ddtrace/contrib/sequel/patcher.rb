require 'ddtrace/ext/sql'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sequel/utils'

module Datadog
  # rubocop:disable Metrics/ModuleLength
  module Contrib
    module Sequel
      # Patcher enables patching of 'sequel' module.
      # This is used in monkey.rb to manually apply patches
      module Patcher
        include Base

        SERVICE = 'sequel'.freeze
        APP = 'sequel'.freeze

        register_as :sequel, auto_patch: false

        @patched = false

        module_function

        # patched? tells whether patch has been successfully applied
        def patched?
          @patched
        end

        def patch
          if !@patched && defined?(::Sequel)
            begin
              patch_sequel_database
              patch_sequel_dataset

              @patched = true
            rescue StandardError
              Datadog::Tracer.log.error('Unable to apply Sequel integration: #{e}')
            end
          end

          @patched
        end

        # rubocop:disable Metrics/MethodLength
        def patch_sequel_database
          ::Sequel::Database.send(:include, Datadog::Contrib::Sequel::Utils)
          ::Sequel::Database.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Patcher.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              pin = Datadog::Pin.new(SERVICE, app: APP, app_type: Datadog::Ext::AppTypes::DB)
              pin.onto(self)
              initialize_without_datadog(*args)
            end

            alias_method :run_without_datadog, :run
            remove_method :run

            def run(sql, options = ::Sequel::OPTS)
              pin = Datadog::Pin.get_from(self)
              return run_without_datadog(sql, options) unless pin && pin.tracer

              opts = parse_opts(sql, options)

              response = nil

              pin.tracer.trace('sequel.query') do |span|
                span.service = pin.service
                span.resource = opts[:query]
                span.span_type = Datadog::Ext::SQL::TYPE
                span.set_tag('sequel.db.vendor', adapter_name)
                response = run_without_datadog(sql, options)
              end
              response
            end
          end
        end

        # rubocop:disable Metrics/AbcSize
        def patch_sequel_dataset
          # rubocop:disable Metrics/BlockLength
          ::Sequel::Dataset.send(:include, Datadog::Contrib::Sequel::Utils)
          ::Sequel::Dataset.class_eval do
            alias_method :initialize_without_datadog, :initialize
            Datadog::Patcher.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              pin = Datadog::Pin.new(SERVICE, app: APP, app_type: Datadog::Ext::AppTypes::DB)
              pin.onto(self)
              initialize_without_datadog(*args)
            end

            alias_method :execute_without_datadog, :execute
            remove_method :execute

            def execute(sql, options = ::Sequel::OPTS, &block)
              pin = Datadog::Pin.get_from(self)
              return execute_without_datadog(sql, options, &block) unless pin && pin.tracer

              opts = parse_opts(sql, options)
              response = nil

              pin.tracer.trace('sequel.query') do |span|
                span.service = pin.service
                span.resource = opts[:query]
                span.span_type = Datadog::Ext::SQL::TYPE
                span.set_tag('sequel.db.vendor', adapter_name)
                response = execute_without_datadog(sql, options, &block)
              end
              response
            end

            alias_method :execute_ddl_without_datadog, :execute_ddl
            remove_method :execute_ddl

            def execute_ddl(sql, options = ::Sequel::OPTS, &block)
              pin = Datadog::Pin.get_from(self)
              return execute_ddl_without_datadog(sql, options, &block) unless pin && pin.tracer

              opts = parse_opts(sql, options)
              response = nil

              pin.tracer.trace('sequel.query') do |span|
                span.service = pin.service
                span.resource = opts[:query]
                span.span_type = Datadog::Ext::SQL::TYPE
                span.set_tag('sequel.db.vendor', adapter_name)
                response = execute_ddl_without_datadog(sql, options, &block)
              end
              response
            end

            alias_method :execute_dui_without_datadog, :execute_dui
            remove_method :execute_dui

            def execute_dui(sql, options = ::Sequel::OPTS, &block)
              pin = Datadog::Pin.get_from(self)
              return execute_dui_without_datadog(sql, options, &block) unless pin && pin.tracer

              opts = parse_opts(sql, options)
              response = nil

              pin.tracer.trace('sequel.query') do |span|
                span.service = pin.service
                span.resource = opts[:query]
                span.span_type = Datadog::Ext::SQL::TYPE
                span.set_tag('sequel.db.vendor', adapter_name)
                response = execute_dui_without_datadog(sql, options, &block)
              end
              response
            end

            alias_method :execute_insert_without_datadog, :execute_insert
            remove_method :execute_insert

            def execute_insert(sql, options = ::Sequel::OPTS, &block)
              pin = Datadog::Pin.get_from(self)
              return execute_insert_without_datadog(sql, options, &block) unless pin && pin.tracer

              opts = parse_opts(sql, options)
              response = nil

              pin.tracer.trace('sequel.query') do |span|
                span.service = pin.service
                span.resource = opts[:query]
                span.span_type = Datadog::Ext::SQL::TYPE
                span.set_tag('sequel.db.vendor', adapter_name)
                response = execute_insert_without_datadog(sql, options, &block)
              end
              response
            end
          end
        end
      end
    end
  end
end
