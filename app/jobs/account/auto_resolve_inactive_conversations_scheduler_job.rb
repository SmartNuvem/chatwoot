class Account::AutoResolveInactiveConversationsSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.with_inactive_conversation_auto_resolve.find_each(batch_size: 100) do |account|
      Conversations::AutoResolveInactiveConversationsJob.perform_later(account: account)
    end
  end
end

Account::AutoResolveInactiveConversationsSchedulerJob.prepend_mod_with('Account::AutoResolveInactiveConversationsSchedulerJob')
