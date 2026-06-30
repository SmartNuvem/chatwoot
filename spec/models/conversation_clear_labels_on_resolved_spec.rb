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
end
