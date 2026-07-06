class Conversations::SendResolvedMessageService
  SOURCE = 'resolved_message'.freeze

  pattr_initialize [:conversation!]

  def perform
    return if conversation.skip_resolved_message
    return unless conversation.resolved?
    return unless conversation.inbox.resolved_message_enabled?

    Conversations::SendAutomationMessageService.new(
      conversation: conversation,
      message_text: conversation.inbox.resolved_message_text,
      source: SOURCE,
      sender: Current.user || conversation.assignee
    ).perform
  end
end
