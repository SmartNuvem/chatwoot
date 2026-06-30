FactoryBot.define do
  factory :webhook do
    account_id { 1 }
    url { 'https://api.chatwoot.com' }
    name { 'My Webhook' }
    transient do
      inbox { nil }
    end
    subscriptions do
      %w[
        conversation_status_changed
        conversation_updated
        conversation_created
        contact_created
        contact_updated
        message_created
        message_updated
        webwidget_triggered
      ]
    end

    after(:create) do |webhook, evaluator|
      webhook.inboxes << evaluator.inbox if evaluator.inbox
    end
  end
end
