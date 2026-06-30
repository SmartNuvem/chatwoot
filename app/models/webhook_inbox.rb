class WebhookInbox < ApplicationRecord
  belongs_to :webhook
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :webhook_id }
  validate :validate_matching_account

  private

  def validate_matching_account
    return if webhook.blank? || inbox.blank?
    return if webhook.account_id == inbox.account_id

    errors.add(:inbox_id, :invalid)
  end
end
