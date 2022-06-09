# encoding: UTF-8

require 'prometheus/client'
require 'prometheus/client/summary'
require 'examples/metric_example'

describe Prometheus::Client::Summary do
  # Reset the data store
  before do
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::Synchronized.new
  end

  let(:expected_labels) { [] }

  let(:summary) do
    Prometheus::Client::Summary.new(:bar,
                                    docstring: 'bar description',
                                    labels: expected_labels)
  end

  it_behaves_like Prometheus::Client::Metric

  describe '#initialization' do
    it 'raise error for `quantile` label' do
      expect do
        described_class.new(:bar, docstring: 'bar description', labels: [:quantile])
      end.to raise_error Prometheus::Client::LabelSetValidator::ReservedLabelError
    end
  end

  describe '#observe' do
    it 'records the given value' do
      expect do
        summary.observe(5)
      end.to change { summary.get }.
        from({ "count" => 0.0, "sum" => 0.0 }).
        to({ "count" => 1.0, "sum" => 5.0 })
    end

    it 'raise error for quantile labels' do
      expect do
        summary.observe(5, labels: { quantile: 1 })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    it 'raises an InvalidLabelSetError if sending unexpected labels' do
      expect do
        summary.observe(5, labels: { foo: 'bar' })
      end.to raise_error Prometheus::Client::LabelSetValidator::InvalidLabelSetError
    end

    context "with a an expected label set" do
      let(:expected_labels) { [:test] }

      it 'observes a value for a given label set' do
        expect do
          expect do
            summary.observe(5, labels: { test: 'value' })
          end.to change { summary.get(labels: { test: 'value' })["count"] }
        end.to_not change { summary.get(labels: { test: 'other' })["count"] }
      end
    end

    context "with non-string label values" do
      let(:summary) do
        described_class.new(:foo,
                            docstring: 'foo description',
                            labels: [:foo])
      end

      it "converts labels to strings for consistent storage" do
        summary.observe(5, labels: { foo: :label })
        expect(summary.get(labels: { foo: 'label' })["count"]).to eq(1.0)
      end

      context "and some labels preset" do
        let(:summary) do
          described_class.new(:foo,
                              docstring: 'foo description',
                              labels: [:foo, :bar],
                              preset_labels: { foo: :label })
        end

        it "converts labels to strings for consistent storage" do
          summary.observe(5, labels: { bar: :label })
          expect(summary.get(labels: { foo: 'label', bar: 'label' })["count"]).to eq(1.0)
        end
      end
    end
  end

  describe '#get' do
    let(:expected_labels) { [:foo] }

    before do
      summary.observe(3, labels: { foo: 'bar' })
      summary.observe(5.2, labels: { foo: 'bar' })
      summary.observe(13, labels: { foo: 'bar' })
      summary.observe(4, labels: { foo: 'bar' })
    end

    it 'returns a value which responds to #sum and #total' do
      expect(summary.get(labels: { foo: 'bar' })).
        to eql({ "count" => 4.0, "sum" => 25.2 })
    end
  end

  describe '#values' do
    let(:expected_labels) { [:status] }

    it 'returns a hash of all recorded summaries' do
      summary.observe(3, labels: { status: 'bar' })
      summary.observe(5, labels: { status: 'foo' })

      expect(summary.values).to eql(
        { status: 'bar' } => { "count" => 1.0, "sum" => 3.0 },
        { status: 'foo' } => { "count" => 1.0, "sum" => 5.0 },
      )
    end
  end

  describe '#init_label_set' do
    context "with labels" do
      let(:expected_labels) { [:status] }

      it 'initializes the metric for a given label set' do
        expect(summary.values).to eql({})

        summary.init_label_set(status: 'bar')
        summary.init_label_set(status: 'foo')

        expect(summary.values).to eql(
          { status: 'bar' } => { "count" => 0.0, "sum" => 0.0 },
          { status: 'foo' } => { "count" => 0.0, "sum" => 0.0 },
        )
      end
    end

    context "without labels" do
      it 'automatically initializes the metric' do
        expect(summary.values).to eql(
          {} => { "count" => 0.0, "sum" => 0.0 },
        )
      end
    end
  end

  describe '#with_labels' do
    let(:expected_labels) { [:foo] }

    it 'pre-sets labels for observations' do
      expect { summary.observe(2) }
        .to raise_error(Prometheus::Client::LabelSetValidator::InvalidLabelSetError)
      expect { summary.with_labels(foo: 'value').observe(2) }.not_to raise_error
    end

    it 'registers `with_labels` observations in the original metric store' do
      summary.observe(1, labels: { foo: 'value1'})
      summary_with_labels = summary.with_labels({ foo: 'value2'})
      summary_with_labels.observe(2)

      expected_values = {
        {foo: 'value1'} => { 'count' => 1.0, 'sum' => 1.0 },
        {foo: 'value2'} => { 'count' => 1.0, 'sum' => 2.0 }
      }
      expect(summary_with_labels.values).to eql(expected_values)
      expect(summary.values).to eql(expected_values)
    end
  end
end
