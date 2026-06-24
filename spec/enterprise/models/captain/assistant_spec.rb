require 'rails_helper'

RSpec.describe Captain::Assistant, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account, additional_attributes: { 'country_code' => 'US' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  describe '#responds_to_audience?' do
    it 'returns true when no audience is configured' do
      expect(assistant.responds_to_audience?(contact, conversation)).to be(true)
    end

    it 'returns true when the contact matches the audience' do
      assistant.update!(config: assistant.config.merge('audience' => {
                                                         'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['US']
                                                       }))
      expect(assistant.responds_to_audience?(contact, conversation)).to be(true)
    end

    it 'returns false when the contact does not match the audience' do
      assistant.update!(config: assistant.config.merge('audience' => {
                                                         'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['CA']
                                                       }))
      expect(assistant.responds_to_audience?(contact, conversation)).to be(false)
    end
  end

  describe '#available_now?' do
    let(:inbox) { create(:inbox, account: account) }
    let(:scheduled_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'is available when the window is blank or always' do
      expect(assistant.available_now?(scheduled_conversation)).to be(true)
      assistant.config['response_window'] = 'always'
      expect(assistant.available_now?(scheduled_conversation)).to be(true)
    end

    it 'is available regardless when the inbox has no business hours configured' do
      inbox.update!(working_hours_enabled: false)
      assistant.config['response_window'] = 'business_hours'
      expect(assistant.available_now?(scheduled_conversation)).to be(true)
    end

    context 'when the inbox has business hours enabled' do
      before { inbox.update!(working_hours_enabled: true) }

      it 'business_hours matches only when the inbox is open' do
        assistant.config['response_window'] = 'business_hours'
        allow(scheduled_conversation.inbox).to receive(:out_of_office?).and_return(false)
        expect(assistant.available_now?(scheduled_conversation)).to be(true)
        allow(scheduled_conversation.inbox).to receive(:out_of_office?).and_return(true)
        expect(assistant.available_now?(scheduled_conversation)).to be(false)
      end

      it 'outside_business_hours matches only when the inbox is closed' do
        assistant.config['response_window'] = 'outside_business_hours'
        allow(scheduled_conversation.inbox).to receive(:out_of_office?).and_return(true)
        expect(assistant.available_now?(scheduled_conversation)).to be(true)
        allow(scheduled_conversation.inbox).to receive(:out_of_office?).and_return(false)
        expect(assistant.available_now?(scheduled_conversation)).to be(false)
      end
    end
  end

  describe 'response_window validation' do
    it 'accepts the known windows' do
      %w[always business_hours outside_business_hours].each do |window|
        assistant.config['response_window'] = window
        expect(assistant).to be_valid
      end
    end

    it 'rejects an unknown window' do
      assistant.config['response_window'] = 'weekends'
      expect(assistant).not_to be_valid
    end
  end

  describe 'audience validation' do
    it 'accepts a well-formed nested tree' do
      assistant.config['audience'] = {
        'operator' => 'and',
        'conditions' => [
          { 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['US'] }
        ]
      }
      expect(assistant).to be_valid
    end

    it 'rejects an unknown operator' do
      assistant.config['audience'] = { 'attribute_key' => 'country_code', 'filter_operator' => 'bogus', 'values' => ['US'] }
      expect(assistant).not_to be_valid
    end

    it 'rejects a group without conditions' do
      assistant.config['audience'] = { 'operator' => 'and', 'conditions' => [] }
      expect(assistant).not_to be_valid
    end

    it 'rejects nesting deeper than one level' do
      assistant.config['audience'] = {
        'operator' => 'and',
        'conditions' => [
          { 'operator' => 'or', 'conditions' => [
            { 'operator' => 'and', 'conditions' => [
              { 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['US'] }
            ] }
          ] }
        ]
      }
      expect(assistant).not_to be_valid
    end
  end
end
