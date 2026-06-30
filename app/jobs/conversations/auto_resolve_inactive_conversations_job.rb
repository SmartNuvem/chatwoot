class Conversations::AutoResolveInactiveConversationsJob < ApplicationJob
  queue_as :low

  def perform(account:)
    Conversations::AutoResolveInactiveConversationsService.new(account: account).perform
  end
end
