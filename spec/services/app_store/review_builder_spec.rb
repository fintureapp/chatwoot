# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppStore::ReviewBuilder do
  let(:channel) { create(:channel_app_store) }
  let(:inbox) { channel.inbox }
  let(:review_payload) do
    {
      'review' => {
        'id' => 'review-1',
        'attributes' => {
          'rating' => 4,
          'title' => 'Helpful app',
          'body' => 'Works well for support.',
          'territory' => 'US',
          'reviewerNickname' => 'Reviewer',
          'createdDate' => '2026-05-20T10:00:00-00:00'
        },
        'relationships' => {
          'response' => {
            'data' => {
              'id' => 'response-1',
              'type' => 'customerReviewResponses'
            }
          }
        }
      },
      'response' => {
        'id' => 'response-1',
        'attributes' => {
          'responseBody' => 'Thanks for the feedback.',
          'state' => 'PUBLISHED',
          'lastModifiedDate' => '2026-05-20T11:00:00-00:00'
        }
      }
    }
  end

  describe '#perform' do
    it 'creates a conversation with an incoming review and outgoing developer response' do
      expect { described_class.new(review_payload: review_payload, channel: channel).perform }
        .to change(inbox.conversations, :count).by(1)
        .and change(Message.where(inbox_id: inbox.id), :count).by(2)

      conversation = inbox.conversations.last
      review_message = conversation.messages.incoming.find_by(source_id: 'review-1')
      response_message = conversation.messages.outgoing.find_by(source_id: 'response-1')

      expect(conversation.contact_inbox.source_id).to eq('review-1')
      expect(review_message.content).to include('★★★★☆ (4/5)', 'Helpful app', 'Works well for support.', 'US • Reviewer')
      expect(review_message.content_attributes['app_store']).to include(
        'rating' => 4,
        'title' => 'Helpful app',
        'territory' => 'US',
        'reviewer_nickname' => 'Reviewer'
      )
      expect(response_message.content).to eq('Thanks for the feedback.')
      expect(response_message.status).to eq('delivered')
    end

    it 'updates an existing review message when Apple returns the same review again' do
      described_class.new(review_payload: review_payload, channel: channel).perform
      updated_payload = review_payload.deep_dup
      updated_payload['review']['attributes']['body'] = 'Updated review body.'

      expect { described_class.new(review_payload: updated_payload, channel: channel).perform }
        .not_to change(Message.where(inbox_id: inbox.id), :count)

      expect(inbox.conversations.last.messages.incoming.find_by(source_id: 'review-1').content).to include('Updated review body.')
    end

    it 'updates an existing developer response message when Apple returns an edited response' do
      described_class.new(review_payload: review_payload, channel: channel).perform
      updated_payload = review_payload.deep_dup
      updated_payload['response']['attributes']['responseBody'] = 'Updated response.'
      updated_payload['response']['attributes']['state'] = 'PENDING_PUBLISH'
      updated_payload['response']['attributes']['lastModifiedDate'] = '2026-05-20T12:00:00-00:00'

      expect { described_class.new(review_payload: updated_payload, channel: channel).perform }
        .not_to change(Message.where(inbox_id: inbox.id), :count)

      response_message = inbox.conversations.last.messages.outgoing.find_by(source_id: 'response-1')
      expect(response_message.content).to eq('Updated response.')
      expect(response_message.content_attributes['app_store']).to include(
        'response_state' => 'PENDING_PUBLISH',
        'response_last_modified_date' => '2026-05-20T12:00:00-00:00'
      )
    end
  end
end
