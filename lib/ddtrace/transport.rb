require 'thread'
require 'net/http'

require 'ddtrace/ext/http'
require 'ddtrace/ext/meta'
require 'ddtrace/encoding'
require 'ddtrace/metrics'

module Datadog
  # Transport class that handles the spans delivery to the
  # local trace-agent. The class wraps a Net:HTTP instance
  # so that the Transport is thread-safe.
  # rubocop:disable Metrics/ClassLength
  class HTTPTransport
    include Datadog::Metrics

    attr_accessor :hostname, :port
    attr_reader :traces_endpoint, :services_endpoint

    # seconds before the transport timeout
    TIMEOUT = 1

    HEADER_TRACE_COUNT = 'X-Datadog-Trace-Count'.freeze

    METRIC_CLIENT_ERROR = 'datadog.tracer.transport.http.client_error'.freeze
    METRIC_INCOMPATIBLE_ERROR = 'datadog.tracer.transport.http.incompatible_error'.freeze
    METRIC_INTERNAL_ERROR = 'datadog.tracer.transport.http.internal_error'.freeze
    METRIC_SERVER_ERROR = 'datadog.tracer.transport.http.server_error'.freeze
    METRIC_SUCCESS = 'datadog.tracer.transport.http.success'.freeze

    TAG_ENCODING_TYPE = 'datadog.tracer.transport.encoding_type'.freeze

    API = {
      V4 = 'v0.4'.freeze => {
        version: V4,
        traces_endpoint: '/v0.4/traces'.freeze,
        services_endpoint: '/v0.4/services'.freeze,
        encoder: Encoding::MsgpackEncoder,
        fallback: 'v0.3'.freeze
      }.freeze,
      V3 = 'v0.3'.freeze => {
        version: V3,
        traces_endpoint: '/v0.3/traces'.freeze,
        services_endpoint: '/v0.3/services'.freeze,
        encoder: Encoding::MsgpackEncoder,
        fallback: 'v0.2'.freeze
      }.freeze,
      V2 = 'v0.2'.freeze => {
        version: V2,
        traces_endpoint: '/v0.2/traces'.freeze,
        services_endpoint: '/v0.2/services'.freeze,
        encoder: Encoding::JSONEncoder
      }.freeze
    }.freeze

    private_constant :API

    def initialize(hostname, port, options = {})
      api_version = options.fetch(:api_version, V3)

      @hostname = hostname
      @port = port
      @api = API.fetch(api_version)
      @encoder = options[:encoder] || @api[:encoder].new
      @response_callback = options[:response_callback]

      # overwrite the Content-type with the one chosen in the Encoder
      @headers = options.fetch(:headers, {})
      @headers['Content-Type'] = @encoder.content_type
      @headers[Ext::HTTP::HEADER_META_LANG] = Ext::Meta::LANG
      @headers[Ext::HTTP::HEADER_META_LANG_INTERPRETER] = Ext::Meta::LANG_INTERPRETER
      @headers[Ext::HTTP::HEADER_META_LANG_VERSION] = Ext::Meta::LANG_VERSION
      @headers[Ext::HTTP::HEADER_META_TRACER_VERSION] = Ext::Meta::TRACER_VERSION

      # stats
      @mutex = Mutex.new
      @count_consecutive_errors = 0
    end

    # route the send to the right endpoint
    def send(endpoint, data)
      case endpoint
      when :services
        payload = @encoder.encode_services(data)
        status_code = post(@api[:services_endpoint], payload) do |response|
          process_callback(:services, response)
        end
      when :traces
        count = data.length
        payload = @encoder.encode_traces(data)
        status_code = post(@api[:traces_endpoint], payload, count) do |response|
          process_callback(:traces, response)
        end
      else
        Datadog::Tracer.log.error("Unsupported endpoint: #{endpoint}")
        return nil
      end

      if downgrade?(status_code)
        downgrade!
        send(endpoint, data)
      else
        status_code
      end
    end

    # send data to the trace-agent; the method is thread-safe
    def post(url, data, count = nil)
      begin
        Datadog::Tracer.log.debug("Sending data from process: #{Process.pid}")
        headers = count.nil? ? {} : { HEADER_TRACE_COUNT => count.to_s }
        headers = headers.merge(@headers)
        request = Net::HTTP::Post.new(url, headers)
        request.body = data

        response = Net::HTTP.start(@hostname, @port, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
          http.request(request)
        end
        handle_response(response)
      rescue StandardError => e
        log_error_once(e.message)
        increment(METRIC_INTERNAL_ERROR)
        500
      end.tap do
        yield(response) if block_given?
      end
    end

    # Downgrade the connection to a compatibility version of the HTTPTransport;
    # this method should target a stable API that works whatever is the agent
    # or the tracing client versions.
    def downgrade!
      @mutex.synchronize do
        fallback_version = @api.fetch(:fallback)

        @api = API.fetch(fallback_version)
        @encoder = @api[:encoder].new
        @headers['Content-Type'] = @encoder.content_type
      end
    end

    def informational?(code)
      code.between?(100, 199)
    end

    def success?(code)
      code.between?(200, 299)
    end

    def redirect?(code)
      code.between?(300, 399)
    end

    def client_error?(code)
      code.between?(400, 499)
    end

    def server_error?(code)
      code.between?(500, 599)
    end

    # receiving a 404 means that we're targeting an endpoint that is not available
    # in the trace agent. Usually this means that we've an up-to-date tracing client,
    # while running an obsolete agent.
    # receiving a 415 means that we're using an unsupported content-type with an existing
    # endpoint. Usually this means that we're using a newer encoder with a previous
    # endpoint. In both cases, we're going to downgrade the transporter encoder so that
    # it will target a stable API.
    def downgrade?(code)
      return unless @api[:fallback]

      code == 404 || code == 415
    end

    # handles the server response; here you can log the trace-agent response
    # or do something more complex to recover from a possible error. This
    # function is handled within the HTTP mutex.synchronize so it's thread-safe.
    def handle_response(response)
      status_code = response.code.to_i

      if success?(status_code)
        Datadog::Tracer.log.debug('Payload correctly sent to the trace agent.')
        @mutex.synchronize { @count_consecutive_errors = 0 }
        increment(METRIC_SUCCESS)
      elsif downgrade?(status_code)
        Datadog::Tracer.log.debug("calling the endpoint but received #{status_code}; downgrading the API")
        increment(METRIC_INCOMPATIBLE_ERROR)
      elsif client_error?(status_code)
        log_error_once("Client error: #{response.message}")
        increment(METRIC_CLIENT_ERROR)
      elsif server_error?(status_code)
        log_error_once("Server error: #{response.message}")
        increment(METRIC_SERVER_ERROR)
      end

      status_code
    rescue StandardError => e
      log_error_once(e.message)
      increment(METRIC_INTERNAL_ERROR)

      500
    end

    private

    def increment(stat)
      # Add default tag to metrics
      super(stat, default_statsd_options)
    end

    def default_statsd_options
      { tags: default_statsd_tags }
    end

    def default_statsd_tags
      ["#{TAG_ENCODING_TYPE}:#{@encoder.content_type}"]
    end

    def log_error_once(*args)
      if @count_consecutive_errors > 0
        Datadog::Tracer.log.debug(*args)
      else
        Datadog::Tracer.log.error(*args)
      end

      @mutex.synchronize { @count_consecutive_errors += 1 }
    end

    def process_callback(action, response)
      return unless @response_callback && @response_callback.respond_to?(:call)

      @response_callback.call(action, response, @api)
    rescue => e
      Tracer.log.debug("Error processing callback: #{e}")
      increment(METRIC_INTERNAL_ERROR)
    end
  end
end
