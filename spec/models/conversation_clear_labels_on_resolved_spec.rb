require 'rails_helper'

RSpec.describe Conversation do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, status: :open) }

  describe 'clearing labels on resolve' do
    it 'keeps labels when the account setting is disabled' do
      conversation.add_labels(%w[support priority_customer])

      conversation.resolved!

      expect(conversation.reload.label_list).to match_array(%w[support priority_customer])
    end

    it 'removes labels when the account setting is enabled' do
      account.update!(settings: { clear_labels_on_resolved: true })
      conversation.add_labels(%w[support priority_customer])

      conversation.resolved!

      expect(conversation.reload.label_list).to be_empty
    end

    it 'does not add labels back when the conversation is reopened' do
      account.update!(settings: { clear_labels_on_resolved: true })
      conversation.add_labels(%w[support priority_customer])
      conversation.resolved!

      conversation.open!

      expect(conversation.reload.label_list).to be_empty
    end
  end

  describe 'sending resolved message on resolve' do
    it 'sends the resolved message when the account setting is enabled' do
      account.update!(
        settings: {
          resolved_message_enabled: true,
          resolved_message_text: 'Atendimento finalizado por {{account.name}}'
        }
      )

      conversation.resolved!

      message = conversation.messages.outgoing.last
      expect(message.content).to eq('Atendimento finalizado por ' + account.name)
      expect(message.content_attributes['automation_source']).to eq(Conversations::SendResolvedMessageService::SOURCE)
    end

    it 'does not send a resolved message when the conversation is reopened' do
      account.update!(settings: { resolved_message_enabled: true, resolved_message_text: 'Atendimento finalizado' })
      conversation.resolved!

      expect { conversation.open! }.not_to change { conversation.messages.outgoing.count }
    end
  end
end
