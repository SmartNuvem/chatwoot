class Conversations::ClearLabelsOnResolvedService
  pattr_initialize [:conversation!]

  def perform
    return unless conversation.account.clear_labels_on_resolved?
    return if conversation.label_list.blank?

    conversation.update_labels([])
  end
end
