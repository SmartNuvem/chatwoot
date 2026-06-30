import {
  CONVERSATION_VISIBILITY_MODES,
  resolveConversationVisibilityMode,
  shouldRestrictConversationsByTeam,
  shouldRestrictConversationsToAssignee,
} from '../teamConversationRestriction';

describe('#resolveConversationVisibilityMode', () => {
  it('returns the configured visibility mode', () => {
    expect(
      resolveConversationVisibilityMode({ conversation_visibility_mode: 2 })
    ).toBe(CONVERSATION_VISIBILITY_MODES.ASSIGNEE);
  });

  it('migrates legacy assignee restriction to assignee mode', () => {
    expect(
      resolveConversationVisibilityMode({
        restrict_conversations_by_team: true,
        restrict_conversations_to_assignee: true,
      })
    ).toBe(CONVERSATION_VISIBILITY_MODES.ASSIGNEE);
  });

  it('migrates legacy team restriction to team mode', () => {
    expect(
      resolveConversationVisibilityMode({
        restrict_conversations_by_team: true,
      })
    ).toBe(CONVERSATION_VISIBILITY_MODES.TEAM);
  });

  it('defaults to default mode', () => {
    expect(resolveConversationVisibilityMode({})).toBe(
      CONVERSATION_VISIBILITY_MODES.DEFAULT
    );
  });

  it('does not treat legacy false strings as enabled', () => {
    expect(
      resolveConversationVisibilityMode({
        restrict_conversations_by_team: 'false',
        restrict_conversations_to_assignee: 'false',
      })
    ).toBe(CONVERSATION_VISIBILITY_MODES.DEFAULT);
  });
});

describe('#shouldRestrictConversationsByTeam', () => {
  it('returns false for administrators when the setting is enabled', () => {
    expect(
      shouldRestrictConversationsByTeam({
        conversationVisibilityMode: CONVERSATION_VISIBILITY_MODES.TEAM,
        role: 'administrator',
      })
    ).toBe(false);
  });

  it('returns true for agents when the setting is enabled', () => {
    expect(
      shouldRestrictConversationsByTeam({
        conversationVisibilityMode: CONVERSATION_VISIBILITY_MODES.TEAM,
        role: 'agent',
      })
    ).toBe(true);
  });

  it('returns false for agents when the setting is disabled', () => {
    expect(
      shouldRestrictConversationsByTeam({
        conversationVisibilityMode: CONVERSATION_VISIBILITY_MODES.DEFAULT,
        role: 'agent',
      })
    ).toBe(false);
  });

  it('returns false when assignee mode is enabled', () => {
    expect(
      shouldRestrictConversationsByTeam({
        conversationVisibilityMode: CONVERSATION_VISIBILITY_MODES.ASSIGNEE,
        role: 'agent',
      })
    ).toBe(false);
  });
});

describe('#shouldRestrictConversationsToAssignee', () => {
  it('returns false for administrators when the setting is enabled', () => {
    expect(
      shouldRestrictConversationsToAssignee({
        conversationVisibilityMode: CONVERSATION_VISIBILITY_MODES.ASSIGNEE,
        role: 'administrator',
      })
    ).toBe(false);
  });

  it('returns true for agents when the setting is enabled', () => {
    expect(
      shouldRestrictConversationsToAssignee({
        conversationVisibilityMode: CONVERSATION_VISIBILITY_MODES.ASSIGNEE,
        role: 'agent',
      })
    ).toBe(true);
  });

  it('returns false for agents when the setting is disabled', () => {
    expect(
      shouldRestrictConversationsToAssignee({
        conversationVisibilityMode: CONVERSATION_VISIBILITY_MODES.DEFAULT,
        role: 'agent',
      })
    ).toBe(false);
  });
});
