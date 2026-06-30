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
           .where('last_activity_at < ?', inactivity_threshold)
           .limit(Limits::BULK_ACTIONS_LIMIT)
  end

  def inactivity_threshold
    Time.current - account.auto_resolve_inactive_conversations_minutes.minutes
  end

  def resolve_conversation(conversation)
    conversation.with_lock do
      conversation.reload
      next unless conversation.open?
      next if conversation.last_activity_at >= inactivity_threshold

      send_auto_resolve_message(conversation)
      conversation.skip_resolved_message = true
      conversation.resolved!
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
end
