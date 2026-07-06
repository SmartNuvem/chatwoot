class Conversations::AutoResolveInactiveConversationsService
  SOURCE = 'auto_resolve_inactive_conversation'.freeze

  pattr_initialize [:account!]

  def perform
    return unless account.auto_resolve_inactive_conversations_enabled?

    inactive_conversations.find_each do |conversation|
      resolve_conversation(conversation)
    end
  end

  private

  def inactive_conversations
    account.conversations.open
           .where.not(contact_id: nil)
           .joins(:messages)
           .merge(human_agent_messages.where('messages.created_at <= ?', inactivity_threshold))
           .distinct
           .limit(Limits::BULK_ACTIONS_LIMIT)
  end

  def inactivity_threshold
    Time.current - account.auto_resolve_inactive_conversations_minutes.minutes
  end

  def resolve_conversation(conversation)
    conversation.with_lock do
      conversation.reload
      last_agent_message = last_human_agent_message(conversation)

      next unless conversation.open?
      next if last_agent_message.blank?
      next if last_agent_message.created_at > inactivity_threshold
      next if incoming_message_after?(conversation, last_agent_message)

      send_auto_resolve_message(conversation)
      conversation.skip_resolved_message = true
      conversation.resolved!
      clear_labels(conversation)
    end
  end

  def send_auto_resolve_message(conversation)
    Conversations::SendAutomationMessageService.new(
      conversation: conversation,
      message_text: account.auto_resolve_inactive_conversations_message,
      source: SOURCE,
      sender: conversation.assignee
    ).perform
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
end
