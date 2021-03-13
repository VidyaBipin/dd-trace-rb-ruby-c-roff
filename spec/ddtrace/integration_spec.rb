require 'spec_helper'

require 'ddtrace'
require 'ddtrace/tracer'
require 'datadog/statsd'

RSpec.describe 'Tracer integration tests' do
  shared_context 'agent-based test' do
    before { skip unless ENV['TEST_DATADOG_INTEGRATION'] }

    after { components.shutdown! }

    let(:settings) do
      Datadog::Configuration::Settings.new
    end

    let(:components) do
      Datadog::Configuration::Components.new(settings)
    end

    def tracer
      components.tracer
    end

    def trace_writer
      components.trace_writer
    end
  end

  shared_examples 'flushed trace' do
    it do
      expect(stats[:traces_flushed]).to eq(1)
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)
    end
  end

  describe 'agent receives span' do
    include_context 'agent-based test'

    def create_trace
      tracer.trace('my.op') do |span|
        span.service = 'my.service'
        sleep(0.001)
      end
    end

    def wait_for_flush(stat, num = 1)
      test_repeat.times do
        break if trace_writer.stats[stat] >= num

        sleep(0.1)
      end
    end

    def agent_receives_span_step1
      stats = trace_writer.stats
      expect(stats[:traces_flushed]).to eq(0)
      expect(stats[:transport].success).to eq(0)
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)
    end

    def agent_receives_span_step2
      create_trace

      # Timeout after 3 seconds, waiting for 1 flush
      wait_for_flush(:traces_flushed)

      stats = trace_writer.stats
      expect(stats[:traces_flushed]).to eq(1)
      expect(stats[:services_flushed]).to be_nil
      # Number of successes will only be 1 since we do not flush services
      expect(stats[:transport].success).to eq(1)
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)

      stats[:transport].success
    end

    def agent_receives_span_step3(previous_success)
      create_trace

      # Timeout after 3 seconds, waiting for another flush
      wait_for_flush(:traces_flushed, 2)

      stats = trace_writer.stats
      expect(stats[:traces_flushed]).to eq(2)
      expect(stats[:services_flushed]).to be_nil
      expect(stats[:transport].success).to be > previous_success
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)
    end

    it do
      agent_receives_span_step1
      success = agent_receives_span_step2
      agent_receives_span_step3(success)
    end
  end

  describe 'agent receives short span' do
    include_context 'agent-based test'

    before do
      tracer.trace('my.short.op') do |span|
        @span = span
        span.service = 'my.service'
      end

      @first_shutdown = trace_writer.stop
    end

    let(:stats) { trace_writer.stats }

    it do
      expect(@first_shutdown).to be true
      expect(@span.finished?).to be true
      expect(stats[:services_flushed]).to be_nil
    end

    it_behaves_like 'flushed trace'
  end

  describe 'rule sampler' do
    include_context 'agent-based test'

    shared_context 'rule sampler' do
      let(:settings) do
        Datadog::Configuration::Settings.new.tap do |settings|
          settings.sampling.sampler = Datadog::PrioritySampler.new(post_sampler: rule_sampler)
        end
      end
    end

    shared_examples 'priority sampled' do |sampling_priority|
      it { expect(@sampling_priority).to eq(sampling_priority) }
    end

    shared_examples 'rule sampling rate metric' do |rate|
      it { expect(@rule_sample_rate).to eq(rate) }
    end

    shared_examples 'rate limit metric' do |rate|
      it { expect(@rate_limiter_rate).to eq(rate) }
    end

    let!(:trace) do
      tracer.trace('my.op') do |span|
        @sampling_priority = span.context.sampling_priority
        @rule_sample_rate = span.get_metric(Datadog::Ext::Sampling::RULE_SAMPLE_RATE)
        @rate_limiter_rate = span.get_metric(Datadog::Ext::Sampling::RATE_LIMITER_RATE)
      end

      trace_writer.stop
    end

    let(:stats) { trace_writer.stats }

    context 'with default settings' do
      it_behaves_like 'flushed trace'
      it_behaves_like 'priority sampled', Datadog::Ext::Priority::AUTO_KEEP
      it_behaves_like 'rule sampling rate metric', nil
      it_behaves_like 'rate limit metric', nil

      context 'with default fallback RateByServiceSampler throttled to 0% sampling rate' do
        let!(:trace) do
          # Force configuration before span is traced
          # DEV: Use MIN because 0.0 is "auto-corrected" to 1.0
          tracer.sampler.update('service:,env:' => Float::MIN)

          super()
        end

        it_behaves_like 'priority sampled', Datadog::Ext::Priority::AUTO_REJECT
      end
    end

    context 'with low default sample rate' do
      include_context 'rule sampler' do
        let(:rule_sampler) { Datadog::Sampling::RuleSampler.new(default_sample_rate: Float::MIN) }
      end

      it_behaves_like 'flushed trace'
      it_behaves_like 'priority sampled', Datadog::Ext::Priority::AUTO_REJECT
      it_behaves_like 'rule sampling rate metric', nil
      it_behaves_like 'rate limit metric', nil
    end

    context 'with rule' do
      include_context 'rule sampler' do
        let(:rule_sampler) { Datadog::Sampling::RuleSampler.new([rule], **rule_sampler_opt) }
        let(:rule_sampler_opt) { {} }
      end

      context 'matching span' do
        let(:rule) { Datadog::Sampling::SimpleRule.new(name: 'my.op') }

        it_behaves_like 'flushed trace'
        it_behaves_like 'priority sampled', Datadog::Ext::Priority::AUTO_KEEP
        it_behaves_like 'rule sampling rate metric', 1.0
        it_behaves_like 'rate limit metric', 1.0

        context 'with low sample rate' do
          let(:rule) { Datadog::Sampling::SimpleRule.new(sample_rate: Float::MIN) }

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Ext::Priority::AUTO_REJECT
          it_behaves_like 'rule sampling rate metric', Float::MIN
          it_behaves_like 'rate limit metric', nil
        end

        context 'rate limited' do
          let(:rule_sampler_opt) { { rate_limit: Float::MIN } }

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Ext::Priority::AUTO_REJECT
          it_behaves_like 'rule sampling rate metric', 1.0
          it_behaves_like 'rate limit metric', 0.0
        end
      end

      context 'not matching span' do
        let(:rule) { Datadog::Sampling::SimpleRule.new(name: 'not.my.op') }

        it_behaves_like 'flushed trace'
        it_behaves_like 'priority sampled', Datadog::Ext::Priority::AUTO_KEEP
        it_behaves_like 'rule sampling rate metric', nil
        it_behaves_like 'rate limit metric', nil
      end
    end
  end

  describe 'shutdown' do
    include_context 'agent-based test'

    context 'executes only once' do
      subject!(:multiple_shutdown) do
        tracer.trace('my.short.op') do |span|
          span.service = 'my.service'
        end

        threads = Array.new(10) do
          Thread.new { trace_writer.stop }
        end

        threads.each(&:join)
      end

      let(:stats) { trace_writer.stats }

      it { expect(stats[:services_flushed]).to be_nil }

      it_behaves_like 'flushed trace'
    end

    context 'when sent TERM' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      subject(:terminated_process) do
        # Initiate IO pipe
        pipe

        # Fork the process
        fork_id = fork do
          allow(Datadog.trace_writer).to receive(:stop).and_wrap_original do |m, *args|
            m.call(*args).tap { write.write(graceful_signal) }
          end

          tracer.trace('my.short.op') do |span|
            span.service = 'my.service'
          end

          sleep(1)
        end

        # Give the fork a chance to setup and sleep
        sleep(0.2)

        # Kill the process
        write.close
        Process.kill('TERM', fork_id) rescue nil

        # Read and return any output
        read.read.tap do
          Process.waitpid(fork_id)
        end
      end

      let(:pipe) { IO.pipe }
      let(:read) { pipe.first }
      let(:write) { pipe.last }
      let(:graceful_signal) { 'graceful' }

      it { expect(terminated_process).to eq(graceful_signal) }
    end
  end

  describe 'sampling priority metrics' do
    include_context 'completed traces'

    # Sampling priority is enabled by default
    let(:tracer) { get_test_tracer }

    context 'when #sampling_priority is set on a child span' do
      let(:parent_span) { tracer.start_span('parent span') }
      let(:child_span) { tracer.start_span('child span', child_of: parent_span.context) }

      before do
        parent_span.tap do
          child_span.tap do
            child_span.context.sampling_priority = 10
          end.finish
        end.finish

        try_wait_until { spans.any? }
      end

      it do
        metric_value = parent_span.get_metric(
          Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY
        )

        expect(metric_value).to eq(10)
      end
    end
  end

  describe 'origin tag' do
    include_context 'completed traces' do
      let(:trace_writer) { FauxWriter.new }

      after do
        trace_writer.stop(true, 5)
      end
    end

    # Sampling priority is enabled by default
    let(:tracer) { get_test_tracer }

    context 'when #sampling_priority is set on a parent span' do
      subject(:tag_value) { parent_span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY) }

      let(:parent_span) { tracer.start_span('parent span') }

      before do
        parent_span.tap do
          parent_span.context.origin = 'synthetics'
        end.finish

        try_wait_until { spans.any? }
      end

      it { is_expected.to eq('synthetics') }
    end
  end

  describe 'sampling priority integration' do
    include_context 'agent-based test'

    # Expect default tracer & tracer instance to both have priority sampling.
    it { expect(Datadog.tracer.sampler).to be_a_kind_of(Datadog::PrioritySampler) }
    it { expect(tracer.sampler).to be_a_kind_of(Datadog::PrioritySampler) }

    it do
      3.times do |i|
        parent_span = tracer.start_span('parent_span')
        child_span = tracer.start_span('child_span', child_of: parent_span.context)

        # I want to keep the trace to which `child_span` belongs
        child_span.context.sampling_priority = i

        child_span.finish
        parent_span.finish

        try_wait_until(attempts: 20) { trace_writer.stats[:traces_flushed] >= 1 }
        stats = trace_writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport].client_error).to eq(0)
        expect(stats[:transport].server_error).to eq(0)
        expect(stats[:transport].internal_error).to eq(0)
      end
    end
  end

  describe 'Transport::IO' do
    include_context 'agent-based test'

    let(:transport) { Datadog::Transport::IO.default(out: out) }
    let(:out) { instance_double(IO) } # Dummy output so we don't pollute STDOUT

    before do
      settings.trace_writer.transport = transport

      # Verify Transport::IO is configured
      expect(trace_writer.transport).to be_a_kind_of(Datadog::Transport::IO::Client)
      expect(trace_writer.transport.encoder).to be(Datadog::Encoding::JSONEncoder)

      # Verify sampling is configured properly
      expect(trace_writer.flush_completed.subscriptions).to include(:priority_sampling)
      expect(tracer.sampler).to be_a_kind_of(Datadog::PrioritySampler)

      # Verify IO is written to
      allow(out).to receive(:puts)

      # Priority sampler does not receive updates because IO is one-way.
      expect(tracer.sampler).to_not receive(:update)
    end

    it do
      3.times do |i|
        parent_span = tracer.start_span('parent_span')
        child_span = tracer.start_span('child_span', child_of: parent_span.context)

        # I want to keep the trace to which `child_span` belongs
        child_span.context.sampling_priority = i

        child_span.finish
        parent_span.finish

        try_wait_until(attempts: 20) { trace_writer.stats[:traces_flushed] >= 1 }
        stats = trace_writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport].client_error).to eq(0)
        expect(stats[:transport].server_error).to eq(0)
        expect(stats[:transport].internal_error).to eq(0)

        expect(out).to have_received(:puts)
      end
    end
  end

  describe 'Transport::HTTP' do
    include_context 'agent-based test'

    let(:transport) { Datadog::Transport::HTTP.default }

    before do
      settings.trace_writer.transport = transport

      # Verify Transport::HTTP is configured
      expect(trace_writer.transport).to be_a_kind_of(Datadog::Transport::Traces::Transport)

      # Verify sampling is configured properly
      expect(trace_writer.flush_completed.subscriptions).to include(:priority_sampling)
      expect(tracer.sampler).to be_a_kind_of(Datadog::PrioritySampler)

      # Verify priority sampler is configured and rates are updated
      expect(tracer.sampler).to receive(:update)
        .with(kind_of(Hash))
        .and_call_original
        .at_least(1).time
    end

    it do
      3.times do |i|
        parent_span = tracer.start_span('parent_span')
        child_span = tracer.start_span('child_span', child_of: parent_span.context)

        # I want to keep the trace to which `child_span` belongs
        child_span.context.sampling_priority = i

        child_span.finish
        parent_span.finish

        try_wait_until(attempts: 20) { trace_writer.stats[:traces_flushed] >= 1 }
        stats = trace_writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport].client_error).to eq(0)
        expect(stats[:transport].server_error).to eq(0)
        expect(stats[:transport].internal_error).to eq(0)
      end
    end
  end

  describe 'Workers::TraceWriter' do
    let(:settings) do
      Datadog::Configuration::Settings.new.tap do |settings|
        settings.trace_writer.instance = Datadog::Workers::TraceWriter.new(transport: transport)
      end
    end

    let(:transport) { Datadog::Transport::HTTP.default { |t| t.adapter :test } }
    let(:components) { Datadog::Configuration::Components.new(settings) }

    def tracer
      components.tracer
    end

    def trace_writer
      components.trace_writer
    end

    before do
      # Measure number of traces flushed
      @traces_flushed = 0
      allow(transport).to receive(:send_traces).and_wrap_original do |m, *args|
        @traces_flushed += args.first.length
        m.call(*args)
      end
    end

    it 'flushes traces successfully' do
      3.times do
        tracer.trace('parent_span') do
          tracer.trace('child_span') do
            # Do work
          end
        end
      end

      expect(@traces_flushed).to eq 3
      transport.stats.tap do |stats|
        expect(stats.success).to be >= 1
        expect(stats.client_error).to eq 0
        expect(stats.server_error).to eq 0
        expect(stats.internal_error).to eq 0
      end
    end
  end

  describe 'Workers::AsyncTraceWriter' do
    let(:settings) do
      Datadog::Configuration::Settings.new.tap do |settings|
        settings.trace_writer.instance = async_trace_writer
      end
    end

    let(:async_trace_writer) do
      Datadog::Workers::AsyncTraceWriter.new(
        transport: transport,
        interval: 0.1 # Shorten interval to make test run faster
      )
    end
    let(:transport) { Datadog::Transport::HTTP.default { |t| t.adapter :test } }
    let(:components) { Datadog::Configuration::Components.new(settings) }

    def tracer
      components.tracer
    end

    def trace_writer
      components.trace_writer
    end

    before do
      # Measure number of traces flushed
      @traces_flushed = 0
      allow(transport).to receive(:send_traces).and_wrap_original do |m, *args|
        @traces_flushed += args.first.length
        m.call(*args)
      end
    end

    after { async_trace_writer.stop(true, 5) }

    it 'flushes traces successfully' do
      3.times do
        tracer.trace('parent_span') do
          tracer.trace('child_span') do
            # Do work
          end
        end
      end

      try_wait_until(attempts: 30) { @traces_flushed == 3 }

      expect(@traces_flushed).to eq 3
      transport.stats.tap do |stats|
        expect(stats.success).to be >= 1
        expect(stats.client_error).to eq 0
        expect(stats.server_error).to eq 0
        expect(stats.internal_error).to eq 0
      end
    end
  end

  describe 'thread-local context' do
    include_context 'completed traces'

    subject(:tracer) { new_tracer }

    it 'clears context after tracer finishes' do
      before = tracer.call_context

      expect(before).to be_a(Datadog::Context)

      span = tracer.trace('test')
      during = tracer.call_context

      expect(during).to be(before)
      expect(during.trace_id).to_not be nil

      span.finish
      after = tracer.call_context

      expect(after).to be(during)
      expect(after.trace_id).to be nil
    end

    it 'reuses context for successive traces' do
      span = tracer.trace('test1')
      context1 = tracer.call_context
      span.finish

      expect(context1).to be_a(Datadog::Context)

      span = tracer.trace('test2')
      context2 = tracer.call_context
      span.finish

      expect(context2).to be(context1)
    end

    context 'with another tracer instance' do
      let(:tracer2) { new_tracer }
      let(:tracer2_traces) { TestTraceBuffer.new }

      before do
        tracer2.trace_completed.subscribe(:test) do |trace|
          tracer2_traces << trace
        end
      end

      it 'create one thread-local context per tracer' do
        span = tracer.trace('test')
        context = tracer.call_context

        span2 = tracer2.trace('test2')
        context2 = tracer2.call_context

        span2.finish
        span.finish

        expect(context).to_not eq(context2)

        expect(spans[0].name).to eq('test')
        expect(tracer2_traces.spans[0].name).to eq('test2')
      end

      context 'with another thread' do
        it 'create one thread-local context per tracer per thread' do
          span = tracer.trace('test')
          context = tracer.call_context

          span2 = tracer2.trace('test2')
          context2 = tracer2.call_context

          Thread.new do
            thread_span = tracer.trace('thread_test')
            @thread_context = tracer.call_context

            thread_span2 = tracer2.trace('thread_test2')
            @thread_context2 = tracer2.call_context

            thread_span.finish
            thread_span2.finish
          end.join

          span2.finish
          span.finish

          expect([context, context2, @thread_context, @thread_context2].uniq)
            .to have(4).items

          expect(spans[0].name).to eq('test')
          expect(spans[1].name).to eq('thread_test')

          spans2 = tracer2_traces.spans
          expect(spans2[0].name).to eq('test2')
          expect(spans2[1].name).to eq('thread_test2')
        end
      end
    end
  end
end
