require 'rails_helper'

RSpec.describe Conversations::ClearLabelsOnResolvedService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#perform' do
    it 'keeps labels when the account setting is disabled' do
      conversation.add_labels(%w[support priority_customer])

      described_class.new(conversation: conversation).perform

      expect(conversation.reload.label_list).to match_array(%w[support priority_customer])
    end

    it 'removes all labels when the account setting is enabled' do
      account.update!(settings: { clear_labels_on_resolved: true })
      conversation.add_labels(%w[support priority_customer])

      described_class.new(conversation: conversation).perform

      expect(conversation.reload.label_list).to be_empty
    end

    it 'does nothing when the conversation has no labels' do
      account.update!(settings: { clear_labels_on_resolved: true })

      described_class.new(conversation: conversation).perform

      expect(conversation.reload.label_list).to be_empty
    end
  end
end
