class AutoAssignUnassignedTeamConversationsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.with_auto_assign_unassigned_team_conversations.find_each do |account|
      next unless claim_interval(account)

      eligible_conversations(account).each do |conversation|
        process_conversation(account, conversation)
      end
    end
  rescue StandardError => e
    Rails.logger.error "[AutoAssignUnassignedTeamConversationsJob] failed: #{e.class.name} #{e.message}"
    raise e if Rails.env.test?
  end

  private

  def process_conversation(account, conversation)
    Rails.logger.info log_message('found unassigned team conversation', conversation)

    result = AutoAssignment::AssignmentService
             .new(inbox: conversation.inbox)
             .perform_for_unassigned_team_conversation(
               conversation,
               require_online_agents: account.auto_assign_unassigned_team_conversations_online_only?
             )

    log_result(conversation, result)
  end

  def log_result(conversation, result)
    case result
    when :assigned
      Rails.logger.info log_message("assigned to agent #{conversation.reload.assignee_id}", conversation)
    when :no_agent_available
      Rails.logger.info log_message('no available team agent found', conversation)
    when :already_assigned
      Rails.logger.info log_message('skipped because conversation is already assigned', conversation)
    when :not_assignable
      Rails.logger.info log_message('skipped because conversation is no longer assignable', conversation)
    end
  end

  def eligible_conversations(account)
    account.conversations
      .open
      .unassigned
      .where.not(team_id: nil)
      .where(
        'conversations.waiting_since IS NOT NULL OR EXISTS ' \
        '(SELECT 1 FROM messages WHERE messages.conversation_id = conversations.id AND messages.message_type = ?)',
        Message.message_types[:incoming]
      )
      .includes(:inbox)
      .reorder(last_activity_at: :asc, created_at: :asc)
      .limit(account.auto_assign_unassigned_team_conversations_batch_limit)
  end

  def claim_interval(account)
    ::Redis::Alfred.set(
      format(::Redis::Alfred::AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_LAST_RUN, account_id: account.id),
      Time.current.to_i,
      nx: true,
      ex: account.auto_assign_unassigned_team_conversations_interval_minutes.minutes
    )
  end

  def log_message(message, conversation)
    "[AutoAssignUnassignedTeamConversationsJob] #{message} " \
      "conversation=#{conversation.id} account=#{conversation.account_id} " \
      "inbox=#{conversation.inbox_id} team=#{conversation.team_id}"
  end
end
