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

export const shouldRestrictConversationsByTeam = ({
  restrictConversationsByTeam,
  role,
}) => !!restrictConversationsByTeam && role !== 'administrator';

export const isTeamConversationRestrictionActive = accountId => {
  const { restrict_conversations_by_team: restrictConversationsByTeam } =
    accountSettings(accountId);

  return shouldRestrictConversationsByTeam({
    restrictConversationsByTeam,
    role: accountRole(accountId),
  });
};

export const redirectRestrictedConversationRoute = async (to, next) => {
  await ensureAccount(to.params.accountId);

  if (!isTeamConversationRestrictionActive(to.params.accountId)) {
    next();
    return;
  }

  await ensureTeams();

  const [firstTeam] = store.getters['teams/getMyTeams'];
  if (firstTeam) {
    next({
      name: 'team_conversations',
      params: {
        accountId: to.params.accountId,
        teamId: firstTeam.id,
      },
    });
    return;
  }

  next({ name: 'home', params: { accountId: to.params.accountId } });
};
