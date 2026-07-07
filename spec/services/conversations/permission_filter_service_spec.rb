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

    context 'when team visibility mode is enabled' do
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
        account.update!(settings: { conversation_visibility_mode: Account::CONVERSATION_VISIBILITY_MODES[:team] })

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
        account.update!(settings: { conversation_visibility_mode: Account::CONVERSATION_VISIBILITY_MODES[:default] })

        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(result).to include(commercial_conversation)
        expect(result).to include(finance_conversation)
        expect(result).to include(unassigned_to_team_conversation)
        expect(result).to include(directly_assigned_conversation)
      end
    end

    context 'when assignee visibility mode is enabled' do
      let(:commercial_agent) { create(:user, account: account, role: :agent) }
      let(:other_agent) { create(:user, account: account, role: :agent) }
      let(:commercial_team) { create(:team, account: account, name: 'Commercial') }
      let(:finance_team) { create(:team, account: account, name: 'Finance') }
      let!(:assigned_to_agent) { create(:conversation, account: account, inbox: inbox, team: commercial_team, assignee: commercial_agent) }
      let!(:assigned_to_other_agent) { create(:conversation, account: account, inbox: inbox, team: commercial_team, assignee: other_agent) }
      let!(:team_unassigned) { create(:conversation, account: account, inbox: inbox, team: commercial_team, assignee: nil) }
      let!(:other_team_conversation) { create(:conversation, account: account, inbox: inbox, team: finance_team, assignee: other_agent) }

      before do
        account.update!(settings: { conversation_visibility_mode: Account::CONVERSATION_VISIBILITY_MODES[:assignee] })

        [commercial_agent, other_agent].each do |user|
          create(:inbox_member, user: user, inbox: inbox)
        end

        create(:team_member, user: commercial_agent, team: commercial_team)
        create(:team_member, user: other_agent, team: commercial_team)
      end

      it 'returns all conversations for administrators' do
        result = described_class.new(account.conversations, admin, account).perform

        expect(result).to include(assigned_to_agent)
        expect(result).to include(assigned_to_other_agent)
        expect(result).to include(team_unassigned)
        expect(result).to include(other_team_conversation)
      end

      it 'returns only conversations assigned directly to the agent' do
        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(result).to include(assigned_to_agent)
        expect(result).not_to include(assigned_to_other_agent)
        expect(result).not_to include(team_unassigned)
        expect(result).not_to include(other_team_conversation)
      end

      it 'takes priority over legacy team restriction' do
        account.update!(
          settings: {
            restrict_conversations_by_team: true,
            conversation_visibility_mode: Account::CONVERSATION_VISIBILITY_MODES[:assignee]
          }
        )

        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(result).to contain_exactly(assigned_to_agent)
      end

      it 'keeps the original behavior when the setting is disabled' do
        account.update!(settings: { conversation_visibility_mode: Account::CONVERSATION_VISIBILITY_MODES[:default] })

        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(result).to include(assigned_to_agent)
        expect(result).to include(assigned_to_other_agent)
        expect(result).to include(team_unassigned)
        expect(result).to include(other_team_conversation)
      end
    end

    context 'when legacy conversation restriction settings exist' do
      let(:commercial_agent) { create(:user, account: account, role: :agent) }
      let(:commercial_team) { create(:team, account: account, name: 'Commercial') }
      let(:finance_team) { create(:team, account: account, name: 'Finance') }
      let!(:commercial_conversation) { create(:conversation, account: account, inbox: inbox, team: commercial_team) }
      let!(:finance_conversation) { create(:conversation, account: account, inbox: inbox, team: finance_team) }
      let!(:assigned_conversation) { create(:conversation, account: account, inbox: inbox, team: finance_team, assignee: commercial_agent) }

      before do
        create(:inbox_member, user: commercial_agent, inbox: inbox)
        create(:team_member, user: commercial_agent, team: commercial_team)
      end

      it 'uses legacy team restriction as team visibility mode' do
        account.update!(settings: { restrict_conversations_by_team: true })

        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(result).to include(commercial_conversation)
        expect(result).to include(assigned_conversation)
        expect(result).not_to include(finance_conversation)
      end

      it 'uses legacy assignee restriction as assignee visibility mode' do
        account.update!(settings: { restrict_conversations_by_team: true, restrict_conversations_to_assignee: true })

        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(result).to contain_exactly(assigned_conversation)
      end
    end

    context 'when assignee visibility mode is stored as a string alias' do
      let(:commercial_agent) { create(:user, account: account, role: :agent) }
      let(:finance_agent) { create(:user, account: account, role: :agent) }
      let!(:assigned_to_commercial) { create(:conversation, account: account, inbox: inbox, assignee: commercial_agent) }
      let!(:assigned_to_finance) { create(:conversation, account: account, inbox: inbox, assignee: finance_agent) }
      let!(:unassigned_conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }

      before do
        account.update!(settings: { conversation_visibility_mode: 'assignee_only' })
        create(:inbox_member, user: commercial_agent, inbox: inbox)
        create(:inbox_member, user: finance_agent, inbox: inbox)
      end

      it 'treats assignee_only as assignee visibility and only returns assigned conversations' do
        result = described_class.new(account.conversations, commercial_agent, account).perform

        expect(account.reload.conversation_visibility_mode).to eq(Account::CONVERSATION_VISIBILITY_MODES[:assignee])
        expect(result).to contain_exactly(assigned_to_commercial)
        expect(result).not_to include(assigned_to_finance, unassigned_conversation)
      end
    end
  end
end
