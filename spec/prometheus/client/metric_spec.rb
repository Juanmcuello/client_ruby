# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/metric'
require 'prometheus/client/data_stores/direct_file_store'

describe Prometheus::Client::Metric do
  let(:test_counter) do
    Class.new(Prometheus::Client::Metric) do
      def type
        :counter
      end

      def increment(by: 1, labels: {})
        raise ArgumentError, 'increment must be a non-negative number' if by < 0

        label_set = label_set_for(labels)
        @store.increment(labels: label_set, by: by)
      end
    end
  end

  let(:expected_labels) { [] }

  subject(:counter) do
    test_counter.new(:foo,
                     docstring: 'foo description',
                     labels: expected_labels)
  end

  describe '#get' do
    it 'returns the current metric value' do
      subject.increment

      expect(subject.get).to eql(1.0)
    end

    context "with a subject that expects labels" do
      subject { test_counter.new(:foo, docstring: 'Labels', labels: [:test]) }

      it 'returns the current metric value for a given label set' do
        subject.increment(labels: { test: 'label' })

        expect(subject.get(labels: { test: 'label' })).to eql(1.0)
      end
    end
  end

  context 'when using DirectFileStore' do
    before do
      Dir.glob('/tmp/prometheus_test/*').each { |file| File.delete(file) }
      Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: '/tmp/prometheus_test')
    end

    let(:expected_labels) { [:foo, :bar] }

    it "doesn't corrupt the data files" do
      counter_with_labels = counter.with_labels({ foo: 'longervalue'})

      # Initialize / read the files for both views of the metric
      counter.increment(labels: { foo: 'value1', bar: 'zzz'})
      counter_with_labels.increment(by: 2, labels: {bar: 'zzz'})

      # After both MetricStores have their files, add a new entry to both
      counter.increment(labels: { foo: 'value1', bar: 'aaa'}) # If there's a bug, we partially overwrite { foo: 'longervalue', bar: 'zzz'}
      counter_with_labels.increment(by: 2, labels: {bar: 'aaa'}) # Extend the file so we read past that overwrite

      expect { counter.values }.not_to raise_error # Check it hasn't corrupted our files
      expect { counter_with_labels.values }.not_to raise_error # Check it hasn't corrupted our files

      expected_values = {
        {foo: 'value1', bar: 'zzz'} => 1.0,
        {foo: 'value1', bar: 'aaa'} => 1.0,
        {foo: 'longervalue', bar: 'zzz'} => 2.0,
        {foo: 'longervalue', bar: 'aaa'} => 2.0,
      }

      expect(counter.values).to eql(expected_values)
      expect(counter_with_labels.values).to eql(expected_values)
    end
  end
end
