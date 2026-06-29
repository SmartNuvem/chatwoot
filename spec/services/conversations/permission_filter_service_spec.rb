require 'rails_helper'

RSpec.describe Conversations::PermissionFilterService do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:another_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }

  # This inbox_member is used to establish the agent's access to the inbox
  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe '#perform' do
    context 'when user is an administrator' do
      it 'returns all conversations' do
        result = described_class.new(
          account.conversations,
          admin,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user is an agent' do
      it 'returns all conversations with no further filtering' do
        inbox_ids = agent.inboxes.where(account_id: account.id).pluck(:id)

        # The base implementation returns all conversations
        # expecting the caller to filter by assigned inboxes
        result = described_class.new(
          account.conversations.where(inbox_id: inbox_ids),
          agent,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when restrict_conversations_by_team is enabled' do
      let(:commercial_agent) { create(:user, account: account, role: :agent) }
      let(:finance_agent) { create(:user, account: account, role: :agent) }
      let(:multi_team_agent) { create(:user, account: account, role: :agent) }
      let(:commercial_team) { create(:team, account: account, name: 'Commercial') }
      let(:finance_team) { create(:team, account: account, name: 'Finance') }
      let!(:commercial_conversation) { create(:conversation, account: account, inbox: inbox, team: commercial_team) }
      let!(:finance_conversation) { create(:conversation, account: account, inbox: inbox, team: finance_team) }
      let!(:unassigned_to_team_conversation) { create(:conversation, account: account, inbox: inbox, team: nil) }
      let!(:directly_assigned_conversation) { create(:conversation, account: account, inbox: inbox, team: nil, assignee: commercial_agent) }

      before do
        account.update!(settings: { restrict_conversations_by_team: true })

        [commercial_agent, finance_agent, multi_team_agent].each do |user|
          create(:inbox_member, user: user, inbox: inbox)
        end

        create(:team_member, user: commercial_agent, team: commercial_team)
        create(:team_member, user: finance_agent, team: finance_team)
        create(:team_member, user: multi_team_agent, team: commercial_team)
        create(:team_member, user: multi_team_agent, team: finance_team)
      end

      it 'returns all conversations for administrators' do
        result = described_class.new(account.conversations, admin, account).perform

        expect(result).to include(commercial_conversation)
        expect(result).to include(finance_conversation)
        expect(result).to include(unassigned_to_team_conversation)
        expect(result).to include(directly_assigned_conversation)
      end

      it 'returns only commercial team conversations and directly assigned conversations for a commercial agent' do
        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(result).to include(commercial_conversation)
        expect(result).to include(directly_assigned_conversation)
        expect(result).not_to include(finance_conversation)
        expect(result).not_to include(unassigned_to_team_conversation)
      end

      it 'does not return commercial conversations for a finance agent' do
        result = described_class.new(account.conversations, finance_agent, account).perform

        expect(result).to include(finance_conversation)
        expect(result).not_to include(commercial_conversation)
        expect(result).not_to include(unassigned_to_team_conversation)
      end

      it 'returns conversations from all teams the agent belongs to' do
        result = described_class.new(account.conversations, multi_team_agent, account).perform

        expect(result).to include(commercial_conversation)
        expect(result).to include(finance_conversation)
        expect(result).not_to include(unassigned_to_team_conversation)
      end

      it 'keeps the original behavior when the setting is disabled' do
        account.update!(settings: { restrict_conversations_by_team: false })

        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(result).to include(commercial_conversation)
        expect(result).to include(finance_conversation)
        expect(result).to include(unassigned_to_team_conversation)
        expect(result).to include(directly_assigned_conversation)
      end
    end
  end
end
