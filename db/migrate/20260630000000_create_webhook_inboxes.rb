class CreateWebhookInboxes < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_inboxes do |t|
      t.references :webhook, null: false, foreign_key: true, index: false
      t.references :inbox, null: false, foreign_key: true, type: :integer

      t.timestamps
    end

    add_index :webhook_inboxes, [:webhook_id, :inbox_id], unique: true
    add_index :webhook_inboxes, :inbox_id
  end
end
