class AutoAssignment::AssignmentService
  pattr_initialize [:inbox!]

  attr_writer :require_online_agents

  def perform_bulk_assignment(limit: 100)
    return 0 unless inbox.auto_assignment_v2_enabled?
    return 0 unless inbox.enable_auto_assignment?

    conversations = unassigned_conversations(limit).to_a
    return 0 if conversations.empty?
    return 0 if inbox.available_agents.empty?

    assigned_count = 0
    conversations.each do |conversation|
      assigned_count += 1 if perform_for_conversation(conversation)
    end
    assigned_count
  end

  def perform_for_unassigned_team_conversation(conversation, require_online_agents: true)
    self.require_online_agents = require_online_agents
    conversation.reload

    return :not_assignable unless inbox.auto_assignment_v2_enabled?
    return :not_assignable unless inbox.enable_auto_assignment?
    return :already_assigned if conversation.assignee_id.present?
    return :not_assignable unless assignable_team_conversation?(conversation)

    agent = find_available_agent(conversation)
    return :no_agent_available unless agent

    assign_conversation(conversation, agent) ? :assigned : :not_assignable
  ensure
    self.require_online_agents = nil
  end

  private

  def perform_for_conversation(conversation)
    return false unless assignable?(conversation)

    agent = find_available_agent(conversation)
    return false unless agent

    assign_conversation(conversation, agent)
  end

  def assignable?(conversation)
    conversation.status == 'open' &&
      conversation.assignee_id.nil?
  end

  def unassigned_conversations(limit)
    scope = inbox.conversations.unassigned.open

    # Skip stale backlog with no activity beyond the policy's age threshold (defaults to 7 days)
    policy = inbox.assignment_policy
    scope = apply_age_exclusions(scope, policy&.exclude_older_than_hours)

    # Apply conversation priority using assignment policy if available
    scope = if policy&.longest_waiting?
              scope.reorder(last_activity_at: :asc, created_at: :asc)
            else
              scope.reorder(created_at: :asc)
            end

    scope.limit(limit)
  end

  def apply_age_exclusions(scope, hours_threshold)
    return scope if hours_threshold.blank?

    hours = hours_threshold.to_i
    return scope unless hours.positive?

    # Use last_activity_at so reopened/active conversations aren't excluded by their original created_at
    scope.where('conversations.last_activity_at >= ?', hours.hours.ago)
  end

  def find_available_agent(conversation = nil)
    agents = filter_agents_by_team(agent_candidates, conversation)
    return nil if agents.nil?

    agents = filter_agents_by_rate_limit(agents)
    return nil if agents.empty?

    round_robin_selector.select_agent(agents)
  end

  def agent_candidates
    return inbox.available_agents if require_online_agents?

    inbox.inbox_members.joins(:user).includes(:user)
  end

  def require_online_agents?
    @require_online_agents.nil? ? true : @require_online_agents
  end

  def filter_agents_by_team(agents, conversation)
    return agents if conversation&.team_id.blank?

    team = conversation.team
    return nil if team.blank? || team.allow_auto_assign.blank?

    team_member_ids = team.members.ids
    agents.where(user_id: team_member_ids)
  end

  def filter_agents_by_rate_limit(agents)
    agents.select do |agent_member|
      rate_limiter = build_rate_limiter(agent_member.user)
      rate_limiter.within_limit?
    end
  end

  def assign_conversation(conversation, agent)
    return false unless claim_and_assign(conversation, agent)

    conversation.reload

    rate_limiter = build_rate_limiter(agent)
    rate_limiter.track_assignment(conversation)

    dispatch_assignment_event(conversation, agent)
    true
  end

  # Atomically claim the row so two bulk runs that overlap (the in-flight gate
  # is best-effort and can lapse on TTL) can't both assign the same conversation.
  def claim_and_assign(conversation, agent)
    Current.executed_by = inbox.assignment_policy || inbox

    Conversation.transaction do
      conditions = { id: conversation.id, assignee_id: nil, status: Conversation.statuses[:open] }
      conditions[:team_id] = conversation.team_id if conversation.team_id.present?

      locked = inbox.conversations.where(conditions).lock('FOR UPDATE SKIP LOCKED').first
      next false unless locked

      locked.update!(assignee: agent)
      true
    end
  ensure
    Current.executed_by = nil
  end

  def dispatch_assignment_event(conversation, agent)
    Rails.configuration.dispatcher.dispatch(
      Events::Types::ASSIGNEE_CHANGED,
      Time.zone.now,
      conversation: conversation,
      user: agent
    )
  end

  def build_rate_limiter(agent)
    AutoAssignment::RateLimiter.new(inbox: inbox, agent: agent)
  end

  def round_robin_selector
    @round_robin_selector ||= AutoAssignment::RoundRobinSelector.new(inbox: inbox)
  end

  def assignable_team_conversation?(conversation)
    conversation.inbox_id == inbox.id &&
      conversation.status == 'open' &&
      conversation.team_id.present? &&
      conversation.assignee_id.nil? &&
      active_conversation?(conversation)
  end

  def active_conversation?(conversation)
    conversation.waiting_since.present? || conversation.messages.incoming.exists?
  end
end

AutoAssignment::AssignmentService.prepend_mod_with('AutoAssignment::AssignmentService')
