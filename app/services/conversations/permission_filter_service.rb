class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  def accessible_conversations
    accessible_by_inbox = conversations.where(inbox: user.inboxes.where(account_id: account.id))

    case account.conversation_visibility_mode
    when Account::CONVERSATION_VISIBILITY_MODES[:assignee]
      accessible_by_inbox.assigned_to(user)
    when Account::CONVERSATION_VISIBILITY_MODES[:team]
      accessible_by_team_or_assignment(accessible_by_inbox)
    else
      accessible_by_inbox
    end
  end

  def accessible_by_team_or_assignment(conversation_scope)
    team_ids = user.teams.where(account_id: account.id).select(:id)

    conversation_scope.where(team_id: team_ids)
                      .or(conversation_scope.assigned_to(user))
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
