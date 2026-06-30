json.id webhook.id
json.name webhook.name
json.url webhook.url
json.account_id webhook.account_id
json.subscriptions webhook.subscriptions
json.secret webhook.secret
json.inbox_ids webhook.inbox_ids
json.inboxes do
  json.array! webhook.inboxes do |inbox|
    json.id inbox.id
    json.name inbox.name
  end
end
