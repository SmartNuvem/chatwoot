class Conversations::SendAutomationMessageService
  AUTOMATION_SOURCE_ATTRIBUTE = 'automation_source'.freeze

  pattr_initialize [:conversation!, :message_text!, :source!, :sender]

  def perform
    return if message_text.blank?
    return if already_sent?

    Messages::MessageBuilder.new(sender || conversation.assignee, conversation, message_params).perform
  end

  private

  def already_sent?
    conversation.messages.outgoing.where("content_attributes ->> 'automation_source' = ?", source).exists?
  end

  def message_params
    {
      content: rendered_message,
      message_type: 'outgoing',
      private: false,
      content_attributes: {
        AUTOMATION_SOURCE_ATTRIBUTE => source
      }
    }
  end

  def rendered_message
    message_text.to_s
                .gsub(/\{\{\s*account\.name\s*\}\}/, conversation.account.name.to_s)
                .gsub(/\{\{\s*contact\.name\s*\}\}/, conversation.contact.name.to_s)
                .gsub(/\{\{\s*agent\.name\s*\}\}/, (sender || conversation.assignee)&.name.to_s)
  end
end
