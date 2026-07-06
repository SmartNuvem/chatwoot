require 'rails_helper'

RSpec.describe Conversations::SendResolvedMessageService do
  let(:account) { create(:account, name: 'Smart Nuvem') }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:agent) { create(:user, account: account, name: 'Ana') }
  let(:conversation) { create(:conversation, account: account, contact: contact, assignee: agent, status: :resolved) }

  describe '#perform' do
    it 'does not send a message when disabled' do
      described_class.new(conversation: conversation).perform

      expect(automation_messages.count).to eq(0)
    end

    it 'sends the configured resolved message' do
      account.update!(
        settings: {
          resolved_message_enabled: true,
          resolved_message_text: 'Obrigado {{contact.name}} - {{account.name}} - {{agent.name}}'
        }
      )

      described_class.new(conversation: conversation).perform

      expect(automation_messages.count).to eq(1)
      expect(automation_messages.last.content).to eq('Obrigado Maria - Smart Nuvem - Ana')
    end

    it 'uses the inbox resolved message when configured' do
      account.update!(settings: { resolved_message_enabled: true, resolved_message_text: 'Obrigado' })
      conversation.inbox.update!(resolved_message_enabled: true, resolved_message_text: 'Finalizado por {{agent.name}}')

      described_class.new(conversation: conversation).perform

      expect(automation_messages.count).to eq(1)
      expect(automation_messages.last.content).to eq('Finalizado por Ana')
    end

    it 'does not send when the inbox disables resolved messages' do
      account.update!(settings: { resolved_message_enabled: true, resolved_message_text: 'Obrigado' })
      conversation.inbox.update!(resolved_message_enabled: false, resolved_message_text: nil)

      described_class.new(conversation: conversation).perform

      expect(automation_messages.count).to eq(0)
    end

    it 'does not send duplicate messages' do
      account.update!(settings: { resolved_message_enabled: true, resolved_message_text: 'Obrigado' })

      2.times { described_class.new(conversation: conversation).perform }

      expect(automation_messages.count).to eq(1)
    end

    it 'does not send when the conversation is not resolved' do
      account.update!(settings: { resolved_message_enabled: true, resolved_message_text: 'Obrigado' })
      conversation.open!

      described_class.new(conversation: conversation).perform

      expect(automation_messages.count).to eq(0)
    end
  end

  def automation_messages
    conversation.messages.outgoing.where("content_attributes ->> 'automation_source' = ?", described_class::SOURCE)
  end
end
