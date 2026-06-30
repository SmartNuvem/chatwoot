require 'rails_helper'

RSpec.describe Conversations::AutoResolveInactiveConversationsService do
  let(:account) { create(:account, name: 'Smart Nuvem') }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:agent) { create(:user, account: account, name: 'Ana') }
  let(:conversation) { create(:conversation, account: account, contact: contact, assignee: agent, status: :open) }

  describe '#perform' do
    it 'does not resolve conversations when disabled' do
      conversation.update!(last_activity_at: 2.hours.ago)

      described_class.new(account: account).perform

      expect(conversation.reload).to be_open
    end

    it 'resolves inactive conversations and sends the configured message' do
      account.update!(
        settings: {
          auto_resolve_inactive_conversations_enabled: true,
          auto_resolve_inactive_conversations_minutes: 30,
          auto_resolve_inactive_conversations_message: 'Olá {{contact.name}} - {{account.name}} - {{agent.name}}'
        }
      )
      conversation.update!(last_activity_at: 31.minutes.ago)

      described_class.new(account: account).perform

      expect(conversation.reload).to be_resolved
      expect(automation_messages.count).to eq(1)
      expect(automation_messages.last.content).to eq('Olá Maria - Smart Nuvem - Ana')
    end

    it 'does not resolve conversations before the configured time' do
      account.update!(
        settings: {
          auto_resolve_inactive_conversations_enabled: true,
          auto_resolve_inactive_conversations_minutes: 30,
          auto_resolve_inactive_conversations_message: 'Finalizando'
        }
      )
      conversation.update!(last_activity_at: 10.minutes.ago)

      described_class.new(account: account).perform

      expect(conversation.reload).to be_open
      expect(automation_messages.count).to eq(0)
    end

    it 'does not send duplicate auto resolve messages' do
      account.update!(
        settings: {
          auto_resolve_inactive_conversations_enabled: true,
          auto_resolve_inactive_conversations_minutes: 30,
          auto_resolve_inactive_conversations_message: 'Finalizando'
        }
      )
      conversation.update!(last_activity_at: 31.minutes.ago)
      create(
        :message,
        account: account,
        inbox: conversation.inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: 'Finalizando',
        content_attributes: { automation_source: described_class::SOURCE }
      )

      described_class.new(account: account).perform

      expect(conversation.reload).to be_resolved
      expect(automation_messages.count).to eq(1)
    end

    it 'runs label cleanup after resolving' do
      account.update!(
        settings: {
          auto_resolve_inactive_conversations_enabled: true,
          auto_resolve_inactive_conversations_minutes: 30,
          auto_resolve_inactive_conversations_message: 'Finalizando',
          clear_labels_on_resolved: true
        }
      )
      conversation.add_labels(%w[support priority_customer])
      conversation.update!(last_activity_at: 31.minutes.ago)

      described_class.new(account: account).perform

      expect(conversation.reload).to be_resolved
      expect(conversation.label_list).to be_empty
    end
  end

  def automation_messages
    conversation.messages.outgoing.where("content_attributes ->> 'automation_source' = ?", described_class::SOURCE)
  end
end
