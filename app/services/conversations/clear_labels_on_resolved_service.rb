class Conversations::ClearLabelsOnResolvedService
  pattr_initialize [:conversation!, { force: false }]

  def perform
    return unless force || conversation.account.clear_labels_on_resolved?
    return if conversation.label_list.blank?

    conversation.update_labels([])
  end
end
