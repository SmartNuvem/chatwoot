class Api::V1::Accounts::WebhooksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_webhook, only: [:update, :destroy]

  def index
    @webhooks = Current.account.webhooks
  end

  def create
    @webhook = Current.account.webhooks.new(webhook_params)
    @webhook.save!
  end

  def update
    @webhook.update!(webhook_params)
  end

  def destroy
    @webhook.destroy!
    head :ok
  end

  private

  def webhook_params
    permitted_params = params.require(:webhook).permit(:inbox_id, :name, :url, inbox_ids: [], subscriptions: [])
    legacy_inbox_id = permitted_params.delete(:inbox_id)
    permitted_params[:inbox_ids] = [legacy_inbox_id] if legacy_inbox_id.present? && permitted_params[:inbox_ids].blank?
    permitted_params
  end

  def fetch_webhook
    @webhook = Current.account.webhooks.find(params[:id])
  end
end
