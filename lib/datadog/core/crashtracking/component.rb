# frozen_string_literal: true

require 'libdatadog'

require_relative 'tag_builder'
require_relative 'agent_base_url'
require_relative '../utils/only_once'
require_relative '../utils/at_fork_monkey_patch'

module Datadog
  module Core
    module Crashtracking
      # Used to report Ruby VM crashes.
      #
      # NOTE: The crashtracker native state is a singleton; so even if you create multiple instances of `Crashtracker`
      # and start them, it only works as "last writer wins". Same for stop -- there's only one state, so calling stop
      # on it will stop the crash tracker, regardless of which instance started it.
      #
      # Methods prefixed with _native_ are implemented in `crashtracker.c`
      class Component
        LIBDATADOG_API_FAILURE =
          begin
            require "libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}"
            nil
          rescue LoadError => e
            e.message
          end

        ONLY_ONCE = Core::Utils::OnlyOnce.new

        def self.build(settings, agent_settings, logger:)
          tags = TagBuilder.call(settings)
          agent_base_url = AgentBaseUrl.resolve(agent_settings)
          logger.warn('Missing agent base URL; cannot enable crash tracking') unless agent_base_url

          ld_library_path = ::Libdatadog.ld_library_path
          logger.warn('Missing ld_library_path; cannot enable crash tracking') unless ld_library_path

          path_to_crashtracking_receiver_binary = ::Libdatadog.path_to_crashtracking_receiver_binary
          unless path_to_crashtracking_receiver_binary
            logger.warn('Missing path_to_crashtracking_receiver_binary; cannot enable crash tracking')
          end

          return unless agent_base_url
          return unless ld_library_path
          return unless path_to_crashtracking_receiver_binary

          new(
            tags: tags,
            agent_base_url: agent_base_url,
            ld_library_path: ld_library_path,
            path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
            logger: logger
          ).tap(&:start)
        end

        def initialize(tags:, agent_base_url:, ld_library_path:, path_to_crashtracking_receiver_binary:, logger:)
          @tags = tags
          @agent_base_url = agent_base_url
          @ld_library_path = ld_library_path
          @path_to_crashtracking_receiver_binary = path_to_crashtracking_receiver_binary
          @logger = logger
        end

        def start
          Utils::AtForkMonkeyPatch.apply!

          start_or_update_on_fork(action: :start)
          ONLY_ONCE.run do
            Utils::AtForkMonkeyPatch.at_fork(:child) do
              start_or_update_on_fork(action: :update_on_fork)
            end
          end
        end

        def stop
          self.class._native_stop
          logger.debug('Crash tracking stopped successfully')
        rescue => e
          logger.error("Failed to stop crash tracking: #{e.message}")
        end

        private

        attr_reader :tags, :agent_base_url, :ld_library_path, :path_to_crashtracking_receiver_binary, :logger

        def start_or_update_on_fork(action:)
          logger.debug("Crash tracking #{action}...")
          self.class._native_start_or_update_on_fork(
            action: action,
            exporter_configuration: [:agent, agent_base_url],
            path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
            ld_library_path: ld_library_path,
            tags_as_array: tags.to_a,
            upload_timeout_seconds: 1
          )
          logger.debug("Crash tracking #{action} successful")
        rescue => e
          logger.error("Failed to #{action} crash tracking: #{e.message}")
        end
      end
    end
  end
end
