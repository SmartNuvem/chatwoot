import { shouldRestrictConversationsByTeam } from '../teamConversationRestriction';

describe('#shouldRestrictConversationsByTeam', () => {
  it('returns false for administrators when the setting is enabled', () => {
    expect(
      shouldRestrictConversationsByTeam({
        restrictConversationsByTeam: true,
        role: 'administrator',
      })
    ).toBe(false);
  });

  it('returns true for agents when the setting is enabled', () => {
    expect(
      shouldRestrictConversationsByTeam({
        restrictConversationsByTeam: true,
        role: 'agent',
      })
    ).toBe(true);
  });

  it('returns false for agents when the setting is disabled', () => {
    expect(
      shouldRestrictConversationsByTeam({
        restrictConversationsByTeam: false,
        role: 'agent',
      })
    ).toBe(false);
  });
});
