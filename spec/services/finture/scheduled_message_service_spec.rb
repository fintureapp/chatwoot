require 'rails_helper'

RSpec.describe Finture::ScheduledMessageService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:template_params) do
    { 'name' => 'sample_shipping_confirmation', 'language' => 'en_US', 'category' => 'SHIPPING_UPDATE',
      'namespace' => '23423423_2342423_324234234_2343224', 'processed_params' => { 'body' => { '1' => '3' } } }
  end

  # Agendamento já vencido (o create exige horário futuro).
  def due_item(attrs = {})
    item = Finture::ScheduledMessage.create!(
      { account: account, conversation: conversation, inbox: inbox, user: agent,
        content: 'Oi, tudo bem?', scheduled_at: 1.minute.from_now, cancel_on_reply: false }.merge(attrs)
    )
    item.update_columns(scheduled_at: 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
    item
  end

  before do
    # Última mensagem do cliente há 2 dias: janela de 24h do WhatsApp fechada.
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 2.days.ago)
  end

  describe '#deliver!' do
    it 'envia o template mesmo com a janela fechada' do
      item = due_item(content: 'Your package has been shipped. It will be delivered in 3 business days.', template_params: template_params)

      described_class.new(scheduled_message: item).deliver!

      item.reload
      expect(item.status).to eq('sent')
      expect(item.message.additional_attributes['template_params']).to include('name' => 'sample_shipping_confirmation')
      expect(item.message.content).to eq(item.content)
    end

    it 'falha a mensagem escrita quando a janela está fechada' do
      item = due_item

      described_class.new(scheduled_message: item).deliver!

      item.reload
      expect(item.status).to eq('failed')
      expect(item.message).to be_nil
      expect(item.error_message).to eq(I18n.t('finture.scheduled_messages.errors.window_closed'))
    end
  end

  describe 'validação do template' do
    it 'exige o nome do template' do
      item = Finture::ScheduledMessage.new(
        account: account, conversation: conversation, inbox: inbox, user: agent,
        content: 'x', scheduled_at: 1.hour.from_now, template_params: { 'language' => 'pt_BR' }
      )

      expect(item).not_to be_valid
      expect(item.errors[:template_params]).to be_present
    end

    it 'recusa variável do template vazia' do
      item = Finture::ScheduledMessage.new(
        account: account, conversation: conversation, inbox: inbox, user: agent, content: 'x', scheduled_at: 1.hour.from_now,
        template_params: template_params.merge('processed_params' => { 'body' => { '1' => '' } })
      )

      expect(item).not_to be_valid
    end
  end
end
