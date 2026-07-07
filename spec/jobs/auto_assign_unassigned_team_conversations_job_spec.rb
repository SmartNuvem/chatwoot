require 'rails_helper'

RSpec.describe AutoAssignUnassignedTeamConversationsJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:assignment_policy) { create(:assignment_policy, account: account, enabled: true) }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent) { create(:user, account: account, role: :agent, availability: :online) }

  before do
    account.enable_features('assignment_v2')
    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: assignment_policy)
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })
    allow(Rails.logger).to receive(:info)
  end

  after do
    Redis::Alfred.delete(format(Redis::Alfred::AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_LAST_RUN, account_id: account.id))
  end

  describe '#perform' do
    it 'assigns an open unassigned conversation in a team to an available team agent' do
      enable_job
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      described_class.new.perform

      expect(conversation.reload.assignee).to eq(agent)
    end

    it 'does not assign conversations without a team' do
      enable_job
      conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      described_class.new.perform

      expect(conversation.reload.assignee).to be_nil
    end

    it 'does not overwrite an existing assignee' do
      enable_job
      assigned_agent = create(:user, account: account, role: :agent)
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: assigned_agent)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      described_class.new.perform

      expect(conversation.reload.assignee).to eq(assigned_agent)
    end

    it 'keeps the team when no team agent is available' do
      enable_job
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      described_class.new.perform

      expect(conversation.reload.assignee).to be_nil
      expect(conversation.team).to eq(team)
    end

    it 'does not assign resolved conversations' do
      enable_job
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil, status: :resolved)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      described_class.new.perform

      expect(conversation.reload.assignee).to be_nil
    end

    it 'respects the configured batch limit' do
      enable_job(batch_limit: 1)
      first = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil, last_activity_at: 2.hours.ago)
      second = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil, last_activity_at: 1.hour.ago)
      create(:message, account: account, inbox: inbox, conversation: first, message_type: :incoming)
      create(:message, account: account, inbox: inbox, conversation: second, message_type: :incoming)

      described_class.new.perform

      expect(first.reload.assignee).to eq(agent)
      expect(second.reload.assignee).to be_nil
    end

    it 'assigns even when inbox auto assignment is disabled' do
      enable_job
      inbox.update!(enable_auto_assignment: false)
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      described_class.new.perform

      expect(conversation.reload.assignee).to eq(agent)
    end

    it 'skips when disabled' do
      conversation = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      described_class.new.perform

      expect(conversation.reload.assignee).to be_nil
    end

    it 'enforces the configured interval' do
      enable_job
      first = create(:conversation, account: account, inbox: inbox, team: team, assignee: nil)
      create(:message, account: account, inbox: inbox, conversation: first, message_type: :incoming)

      described_class.new.perform
      first.update!(assignee: nil)
      described_class.new.perform

      expect(Rails.logger).to have_received(:info).with(/found unassigned team conversation/).once
    end
  end

  def enable_job(batch_limit: 100)
    account.update!(
      settings: account.settings.merge(
        'auto_assign_unassigned_team_conversations_enabled' => true,
        'auto_assign_unassigned_team_conversations_interval_minutes' => 15,
        'auto_assign_unassigned_team_conversations_online_only' => true,
        'auto_assign_unassigned_team_conversations_batch_limit' => batch_limit
      )
    )
  end
end
