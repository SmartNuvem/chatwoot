class AddResolvedMessageSettingsToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :resolved_message_enabled, :boolean
    add_column :inboxes, :resolved_message_text, :text
    add_column :inboxes, :auto_resolve_inactive_conversations_enabled, :boolean
    add_column :inboxes, :auto_resolve_inactive_conversations_minutes, :integer
  end
end
