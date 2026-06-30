import store from 'dashboard/store';

const accountRole = accountId => {
  const { accounts = [] } = store.getters.getCurrentUser || {};
  const account = accounts.find(({ id }) => Number(id) === Number(accountId));
  return account?.role;
};

const accountSettings = accountId => {
  const account = store.getters['accounts/getAccount'](Number(accountId)) || {};
  return account.settings || {};
};

const ensureAccount = async accountId => {
  const account = store.getters['accounts/getAccount'](Number(accountId)) || {};
  if (account.id) return;

  await store.dispatch('accounts/get', { silent: true });
};

const ensureTeams = async () => {
  if (store.getters['teams/getTeams'].length) return;

  await store.dispatch('teams/get');
};

export const CONVERSATION_VISIBILITY_MODES = {
  DEFAULT: 0,
  TEAM: 1,
  ASSIGNEE: 2,
};

const isEnabled = value => value === true || value === 'true';

export const resolveConversationVisibilityMode = (settings = {}) => {
  const { conversation_visibility_mode: conversationVisibilityMode } = settings;

  if (
    conversationVisibilityMode !== undefined &&
    conversationVisibilityMode !== null &&
    conversationVisibilityMode !== ''
  ) {
    return Number(conversationVisibilityMode);
  }

  if (isEnabled(settings.restrict_conversations_to_assignee)) {
    return CONVERSATION_VISIBILITY_MODES.ASSIGNEE;
  }

  if (isEnabled(settings.restrict_conversations_by_team)) {
    return CONVERSATION_VISIBILITY_MODES.TEAM;
  }

  return CONVERSATION_VISIBILITY_MODES.DEFAULT;
};

export const shouldRestrictConversationsByTeam = ({
  conversationVisibilityMode,
  role,
}) =>
  conversationVisibilityMode === CONVERSATION_VISIBILITY_MODES.TEAM &&
  role !== 'administrator';

export const shouldRestrictConversationsToAssignee = ({
  conversationVisibilityMode,
  role,
}) =>
  conversationVisibilityMode === CONVERSATION_VISIBILITY_MODES.ASSIGNEE &&
  role !== 'administrator';

export const isAssigneeConversationRestrictionActive = accountId => {
  return shouldRestrictConversationsToAssignee({
    conversationVisibilityMode: resolveConversationVisibilityMode(
      accountSettings(accountId)
    ),
    role: accountRole(accountId),
  });
};

export const isTeamConversationRestrictionActive = accountId => {
  return shouldRestrictConversationsByTeam({
    conversationVisibilityMode: resolveConversationVisibilityMode(
      accountSettings(accountId)
    ),
    role: accountRole(accountId),
  });
};

const homeRoute = accountId => ({
  name: 'home',
  params: { accountId },
});

export const restrictedConversationRouteRedirect = async to => {
  await ensureAccount(to.params.accountId);

  if (isAssigneeConversationRestrictionActive(to.params.accountId)) {
    return homeRoute(to.params.accountId);
  }

  if (['team_conversations', 'conversations_through_team'].includes(to.name)) {
    return null;
  }

  if (!isTeamConversationRestrictionActive(to.params.accountId)) {
    return null;
  }

  await ensureTeams();

  const [firstTeam] = store.getters['teams/getMyTeams'];
  if (firstTeam) {
    return {
      name: 'team_conversations',
      params: {
        accountId: to.params.accountId,
        teamId: firstTeam.id,
      },
    };
  }

  return homeRoute(to.params.accountId);
};

export const assigneeRestrictedConversationRouteRedirect = async to => {
  await ensureAccount(to.params.accountId);

  if (isAssigneeConversationRestrictionActive(to.params.accountId)) {
    return homeRoute(to.params.accountId);
  }

  return null;
};

export const redirectRestrictedConversationRoute = async (to, next) => {
  const redirect = await restrictedConversationRouteRedirect(to);

  if (redirect) {
    next(redirect);
    return;
  }

  next();
};

export const redirectAssigneeRestrictedConversationRoute = async (to, next) => {
  const redirect = await assigneeRestrictedConversationRouteRedirect(to);

  if (redirect) {
    next(redirect);
    return;
  }

  next();
};
