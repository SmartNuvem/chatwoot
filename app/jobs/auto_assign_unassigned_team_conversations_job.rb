class AutoAssignUnassignedTeamConversationsJob < ApplicationJob
  queue_as :scheduled_jobs

  DEFAULT_INTERVAL_MINUTES = 15
  DEFAULT_BATCH_LIMIT = 100

  def perform
    return unless enabled?
    return unless claim_interval

    eligible_conversations.each do |conversation|
      process_conversation(conversation)
    end
  rescue StandardError => e
    Rails.logger.error "[AutoAssignUnassignedTeamConversationsJob] failed: #{e.class.name} #{e.message}"
    raise e if Rails.env.test?
  end

  private

  def process_conversation(conversation)
    Rails.logger.info log_message('found unassigned team conversation', conversation)

    result = AutoAssignment::AssignmentService
             .new(inbox: conversation.inbox)
             .perform_for_unassigned_team_conversation(
               conversation,
               require_online_agents: require_online_agents?
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

  def eligible_conversations
    Conversation
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
      .limit(batch_limit)
  end

  def claim_interval
    ::Redis::Alfred.set(
      ::Redis::Alfred::AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_LAST_RUN,
      Time.current.to_i,
      nx: true,
      ex: interval_minutes.minutes
    )
  end

  def enabled?
    boolean_config('AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_ENABLED', false)
  end

  def require_online_agents?
    boolean_config('AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_ONLINE_ONLY', true)
  end

  def interval_minutes
    integer_config('AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_INTERVAL_MINUTES', DEFAULT_INTERVAL_MINUTES, minimum: 1)
  end

  def batch_limit
    integer_config('AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_BATCH_LIMIT', DEFAULT_BATCH_LIMIT, minimum: 1)
  end

  def boolean_config(key, default)
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load(key, default.to_s))
  end

  def integer_config(key, default, minimum:)
    value = GlobalConfigService.load(key, default.to_s).to_i
    value >= minimum ? value : default
  end

  def log_message(message, conversation)
    "[AutoAssignUnassignedTeamConversationsJob] #{message} " \
      "conversation=#{conversation.id} account=#{conversation.account_id} " \
      "inbox=#{conversation.inbox_id} team=#{conversation.team_id}"
  end
end
