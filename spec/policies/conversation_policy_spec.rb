require 'rails_helper'

RSpec.describe ConversationPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:conversation) { create(:conversation, account: account) }

  permissions :destroy? do
    context 'when user is an administrator' do
      it 'allows destroy' do
        expect(subject).to permit(administrator_context, conversation)
      end
    end

    context 'when user is an agent' do
      it 'denies destroy' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end
  end

  permissions :index? do
    context 'when user is authenticated' do
      it 'allows index' do
        expect(subject).to permit(agent_context, conversation)
      end
    end
  end

  permissions :show? do
    context 'when user is an administrator' do
      it 'allows access' do
        expect(subject).to permit(administrator_context, conversation)
      end
    end

    context 'when agent has inbox access' do
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'allows access' do
        expect(subject).to permit(agent_context, conversation)
      end
    end

    context 'when agent has team access' do
      let(:team) { create(:team, account: account) }
      let(:conversation) { create(:conversation, :with_team, account: account, team: team) }

      before { create(:team_member, team: team, user: agent) }

      it 'allows access' do
        expect(subject).to permit(agent_context, conversation)
      end
    end

    context 'when agent lacks inbox and team access' do
      let(:conversation) { create(:conversation, account: account) }

      it 'denies access' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end

    context 'when team visibility mode is enabled' do
      let(:inbox) { create(:inbox, account: account) }
      let(:team) { create(:team, account: account) }

      before do
        account.update!(settings: { conversation_visibility_mode: Account::CONVERSATION_VISIBILITY_MODES[:team] })
        create(:inbox_member, user: agent, inbox: inbox)
      end

      it 'denies access to conversations from accessible inboxes without team access' do
        restricted_conversation = create(:conversation, account: account, inbox: inbox)

        expect(subject).not_to permit(agent_context, restricted_conversation)
      end

      it 'allows access to conversations assigned directly to the agent' do
        assigned_conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect(subject).to permit(agent_context, assigned_conversation)
      end

      it 'allows access to conversations assigned to the agent team' do
        create(:team_member, user: agent, team: team)
        team_conversation = create(:conversation, account: account, inbox: inbox, team: team)

        expect(subject).to permit(agent_context, team_conversation)
      end
    end

    context 'when assignee visibility mode is enabled' do
      let(:inbox) { create(:inbox, account: account) }
      let(:team) { create(:team, account: account) }
      let(:other_agent) { create(:user, account: account, role: :agent) }

      before do
        account.update!(settings: { conversation_visibility_mode: Account::CONVERSATION_VISIBILITY_MODES[:assignee] })
        create(:inbox_member, user: agent, inbox: inbox)
        create(:team_member, user: agent, team: team)
      end

      it 'allows access to conversations assigned directly to the agent' do
        assigned_conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent)

        expect(subject).to permit(agent_context, assigned_conversation)
      end

      it 'denies access to team conversations assigned to another agent' do
        assigned_to_other = create(:conversation, account: account, inbox: inbox, team: team, assignee: other_agent)

        expect(subject).not_to permit(agent_context, assigned_to_other)
      end

      it 'denies access to team conversations without an assignee' do
        team_conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil)

        expect(subject).not_to permit(agent_context, team_conversation)
      end
    end
  end
end
