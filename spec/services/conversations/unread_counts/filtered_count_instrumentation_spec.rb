require 'rails_helper'

RSpec.describe Conversations::UnreadCounts::FilteredCountInstrumentation do
  let(:new_relic_agent) do
    Class.new do
      def self.record_custom_event(*) end
      def self.record_metric(*) end
    end
  end

  before do
    stub_const('NewRelic::Agent', new_relic_agent)
    allow(new_relic_agent).to receive(:record_custom_event)
    allow(new_relic_agent).to receive(:record_metric)
  end

  describe '.observe' do
    it 'records duration metrics and custom events around successful operations' do
      result = described_class.observe(:counter_perform, account_id: 1, snapshot_scope: :built_in_filter) { 'ok' }

      expect(result).to eq('ok')
      expect(new_relic_agent).to have_received(:record_custom_event).with(
        'FilteredUnreadCounts',
        hash_including(
          account_id: 1,
          duration_ms: kind_of(Float),
          operation: 'counter_perform',
          snapshot_scope: 'built_in_filter',
          status: 'success'
        )
      )
      expect(new_relic_agent).to have_received(:record_metric).with(
        'Custom/Conversations/UnreadCounts/Filtered/counter_perform/duration_ms',
        kind_of(Float)
      )
    end

    it 'records failed operations and re-raises the original error' do
      error = StandardError.new('boom')

      expect do
        described_class.observe(:snapshot_build, account_id: 1) { raise error }
      end.to raise_error(error)
      expect(new_relic_agent).to have_received(:record_custom_event).with(
        'FilteredUnreadCounts',
        hash_including(
          account_id: 1,
          error_class: 'StandardError',
          operation: 'snapshot_build',
          status: 'error'
        )
      )
    end
  end

  describe '.increment' do
    it 'records count metrics and custom events' do
      described_class.increment(:snapshot_state, account_id: 1, snapshot_status: :fresh)

      expect(new_relic_agent).to have_received(:record_custom_event).with(
        'FilteredUnreadCounts',
        hash_including(
          account_id: 1,
          operation: 'snapshot_state',
          snapshot_status: 'fresh'
        )
      )
      expect(new_relic_agent).to have_received(:record_metric).with(
        'Custom/Conversations/UnreadCounts/Filtered/snapshot_state/count',
        1
      )
    end

    it 'does not raise when New Relic is unavailable' do
      allow(described_class).to receive(:new_relic_agent).and_return(nil)

      expect { described_class.increment(:snapshot_state, account_id: 1) }.not_to raise_error
    end
  end
end
