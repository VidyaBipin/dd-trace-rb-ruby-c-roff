module Datadog
  module Ext
    module Profiling
      ENV_MAX_FRAMES = 'DD_PROFILING_MAX_FRAMES'.freeze
      ENV_MAX_TIME_USAGE_PCT = 'DD_PROFILING_MAX_TIME_USAGE_PCT'.freeze
      ENV_IGNORE_PROFILER = 'DD_PROFILING_IGNORE_PROFILER'.freeze

      module Pprof
        LABEL_KEY_THREAD_ID = 'thread id'.freeze
        SAMPLE_VALUE_NO_VALUE = 0
        VALUE_TYPE_CPU = 'cpu-time'.freeze
        VALUE_TYPE_WALL = 'wall-time'.freeze
        VALUE_UNIT_NANOSECONDS = 'nanoseconds'.freeze
      end

      module Transport
        module HTTP
          URI_TEMPLATE_DD_API = 'https://intake.profile.%s/'.freeze

          FORM_FIELD_DATA = 'data[0]'.freeze
          FORM_FIELD_FORMAT = 'format'.freeze
          FORM_FIELD_FORMAT_PPROF = 'pprof'.freeze
          FORM_FIELD_RECORDING_END = 'recording-end'.freeze
          FORM_FIELD_RECORDING_START = 'recording-start'.freeze
          FORM_FIELD_RUNTIME = 'runtime'.freeze
          FORM_FIELD_RUNTIME_ID = 'runtime-id'.freeze
          FORM_FIELD_TAG_ENV = 'env'.freeze
          FORM_FIELD_TAG_HOST = 'host'.freeze
          FORM_FIELD_TAG_LANGUAGE = 'language'.freeze
          FORM_FIELD_TAG_PROFILER_VERSION = 'profiler_version'.freeze
          FORM_FIELD_TAG_RUNTIME = 'runtime'.freeze
          FORM_FIELD_TAG_RUNTIME_VERSION = 'runtime_version'.freeze
          FORM_FIELD_TAG_SERVICE = 'service'.freeze
          FORM_FIELD_TAG_VERSION = 'version'.freeze
          FORM_FIELD_TAGS = 'tags'.freeze
          FORM_FIELD_TYPES = 'types'.freeze
          FORM_FIELD_TYPE_CPU_TIME = 'cpu_time'.freeze

          HEADER_CONTENT_TYPE = 'Content-Type'.freeze
          HEADER_CONTENT_TYPE_OCTET_STREAM = 'application/octet-stream'.freeze

          PPROF_DEFAULT_FILENAME = 'profile.pb.gz'.freeze
        end
      end
    end
  end
end
