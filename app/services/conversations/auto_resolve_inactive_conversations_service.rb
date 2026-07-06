class Conversations::AutoResolveInactiveConversationsService
  SOURCE = 'auto_resolve_inactive_conversation'.freeze

  pattr_initialize [:account!]

  def perform
    return unless auto_resolve_configured?

    inactive_conversations.find_each do |conversation|
      resolve_conversation(conversation)
    end
  end

  private

  def inactive_conversations
    account.conversations.open
           .where.not(contact_id: nil)
           .joins(:inbox, :messages)
           .merge(human_agent_messages)
           .where(auto_resolve_enabled_condition, account.auto_resolve_inactive_conversations_enabled?)
           .where(agent_message_older_than_configured_minutes_condition, account.auto_resolve_inactive_conversations_minutes)
           .distinct
           .limit(Limits::BULK_ACTIONS_LIMIT)
  end

  def auto_resolve_configured?
    account.auto_resolve_inactive_conversations_enabled? ||
      account.inboxes.where(auto_resolve_inactive_conversations_enabled: true).exists?
  end

  def resolve_conversation(conversation)
    conversation.with_lock do
      conversation.reload
      last_agent_message = last_human_agent_message(conversation)

      next unless conversation.open?
      next unless conversation.inbox.auto_resolve_inactive_conversations_enabled?
      next if last_agent_message.blank?
      next if last_agent_message.created_at > inactivity_threshold(conversation)
      next if incoming_message_after?(conversation, last_agent_message)

      send_auto_resolve_message(conversation)
      conversation.skip_resolved_message = true
      conversation.resolved!
      clear_labels(conversation)
    end
  end

  def send_auto_resolve_message(conversation)
    return unless conversation.inbox.resolved_message_enabled?

    Conversations::SendAutomationMessageService.new(
      conversation: conversation,
      message_text: resolved_message_text(conversation),
      source: SOURCE,
      sender: conversation.assignee
    ).perform
  end

  def resolved_message_text(conversation)
    conversation.inbox[:resolved_message_text].presence || account.auto_resolve_inactive_conversations_message
  end

  def inactivity_threshold(conversation)
    Time.current - conversation.inbox.auto_resolve_inactive_conversations_minutes.minutes
  end

  def clear_labels(conversation)
    Conversations::ClearLabelsOnResolvedService.new(conversation: conversation, force: true).perform
  end

  def last_human_agent_message(conversation)
    human_agent_messages
      .where(conversation_id: conversation.id)
      .reorder(created_at: :desc, id: :desc)
      .first
  end

  def incoming_message_after?(conversation, message)
    conversation.messages.incoming
                .where('created_at > ? OR (created_at = ? AND id > ?)', message.created_at, message.created_at, message.id)
                .exists?
  end

  def human_agent_messages
    Message.outgoing
           .reorder(nil)
           .where(account_id: account.id, private: false, sender_type: 'User')
           .where("content_attributes ->> 'automation_rule_id' IS NULL")
           .where("content_attributes ->> 'automation_source' IS NULL")
           .where("additional_attributes ->> 'campaign_id' IS NULL")
  end

  def auto_resolve_enabled_condition
    'COALESCE(inboxes.auto_resolve_inactive_conversations_enabled, ?) = TRUE'
  end

  def agent_message_older_than_configured_minutes_condition
    "messages.created_at <= CURRENT_TIMESTAMP - (COALESCE(inboxes.auto_resolve_inactive_conversations_minutes, ?) * INTERVAL '1 minute')"
  end
end
