<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import WithLabel from 'v3/components/Form/WithLabel.vue';
import NextInput from 'next/input/Input.vue';
import Switch from 'next/switch/Switch.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import AccountId from './components/AccountId.vue';
import BuildInfo from './components/BuildInfo.vue';
import AccountDelete from './components/AccountDelete.vue';
import AudioTranscription from './components/AudioTranscription.vue';
import SectionLayout from './components/SectionLayout.vue';
import {
  resolveConversationVisibilityMode,
  CONVERSATION_VISIBILITY_MODES,
} from 'dashboard/helper/teamConversationRestriction';

const DEFAULT_RESOLVED_MESSAGE_TEXT = `Agradecemos por entrar em contato conosco 😊

Permanecemos à disposição para qualquer necessidade futura.

Desejamos um excelente dia!

Atenciosamente,
Equipe {{account.name}}`;

const DEFAULT_AUTO_RESOLVE_INACTIVE_CONVERSATIONS_MESSAGE = `Como não tivemos novas interações, estamos finalizando este atendimento automaticamente. 😊

Caso precise de algo, basta enviar uma nova mensagem.

Atenciosamente,
Equipe {{account.name}}`;

export default {
  components: {
    BaseSettingsHeader,
    NextButton,
    AccountId,
    BuildInfo,
    AccountDelete,
    AudioTranscription,
    SectionLayout,
    WithLabel,
    NextInput,
    Switch,
  },
  setup() {
    const { updateUISettings, uiSettings } = useUISettings();
    const { enabledLanguages } = useConfig();
    const { accountId } = useAccount();
    const v$ = useVuelidate();

    return { updateUISettings, uiSettings, v$, enabledLanguages, accountId };
  },
  data() {
    return {
      id: '',
      name: '',
      locale: 'en',
      domain: '',
      supportEmail: '',
      conversationVisibilityMode: CONVERSATION_VISIBILITY_MODES.DEFAULT,
      clearLabelsOnResolved: false,
      resolvedMessageEnabled: false,
      resolvedMessageText: DEFAULT_RESOLVED_MESSAGE_TEXT,
      autoResolveInactiveConversationsEnabled: false,
      autoResolveInactiveConversationsMinutes: 60,
      autoResolveInactiveConversationsMessage:
        DEFAULT_AUTO_RESOLVE_INACTIVE_CONVERSATIONS_MESSAGE,
      features: {},
    };
  },
  validations: {
    name: {
      required,
    },
    locale: {
      required,
    },
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      uiFlags: 'accounts/getUIFlags',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      isOnChatwootCloud: 'globalConfig/isOnChatwootCloud',
    }),
    showAudioTranscriptionConfig() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.CAPTAIN
      );
    },
    languagesSortedByCode() {
      const enabledLanguages = [...this.enabledLanguages];
      return enabledLanguages.sort((l1, l2) =>
        l1.iso_639_1_code.localeCompare(l2.iso_639_1_code)
      );
    },
    isUpdating() {
      return this.uiFlags.isUpdating;
    },
    featureInboundEmailEnabled() {
      return !!this.features?.inbound_emails;
    },
    featureCustomReplyDomainEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_domain
      );
    },
    featureCustomReplyEmailEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_email
      );
    },
    currentAccount() {
      return this.getAccount(this.accountId) || {};
    },
    conversationVisibilityOptions() {
      return [
        {
          value: CONVERSATION_VISIBILITY_MODES.DEFAULT,
          label: this.$t(
            'GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.OPTIONS.DEFAULT.LABEL'
          ),
          description: this.$t(
            'GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.OPTIONS.DEFAULT.DESCRIPTION'
          ),
        },
        {
          value: CONVERSATION_VISIBILITY_MODES.TEAM,
          label: this.$t(
            'GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.OPTIONS.TEAM.LABEL'
          ),
          description: this.$t(
            'GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.OPTIONS.TEAM.DESCRIPTION'
          ),
        },
        {
          value: CONVERSATION_VISIBILITY_MODES.ASSIGNEE,
          label: this.$t(
            'GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.OPTIONS.ASSIGNEE.LABEL'
          ),
          description: this.$t(
            'GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.OPTIONS.ASSIGNEE.DESCRIPTION'
          ),
        },
      ];
    },
  },
  watch: {
    'currentAccount.id'(id) {
      if (id) {
        this.initializeAccount();
      }
    },
  },
  mounted() {
    // Account already in the store (navigated in): seed immediately.
    if (this.currentAccount.id) {
      this.initializeAccount();
    }
  },
  methods: {
    async initializeAccount() {
      try {
        const { name, locale, id, domain, support_email, features, settings } =
          this.getAccount(this.accountId);

        const effectiveLocale = this.uiSettings?.locale || locale;
        if (effectiveLocale) {
          this.$root.$i18n.locale = effectiveLocale;
        }
        this.name = name;
        this.locale = locale;
        this.id = id;
        this.domain = domain;
        this.supportEmail = support_email;
        this.conversationVisibilityMode =
          resolveConversationVisibilityMode(settings);
        this.clearLabelsOnResolved = !!settings?.clear_labels_on_resolved;
        this.resolvedMessageEnabled = !!settings?.resolved_message_enabled;
        this.resolvedMessageText =
          settings?.resolved_message_text || DEFAULT_RESOLVED_MESSAGE_TEXT;
        this.autoResolveInactiveConversationsEnabled =
          !!settings?.auto_resolve_inactive_conversations_enabled;
        this.autoResolveInactiveConversationsMinutes =
          Number(settings?.auto_resolve_inactive_conversations_minutes || 60);
        this.autoResolveInactiveConversationsMessage =
          settings?.auto_resolve_inactive_conversations_message ||
          DEFAULT_AUTO_RESOLVE_INACTIVE_CONVERSATIONS_MESSAGE;
        this.features = features;
      } catch (error) {
        // Ignore error
      }
    },

    async updateAccount() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.ERROR'));
        return;
      }
      try {
        await this.$store.dispatch('accounts/update', {
          locale: this.locale,
          name: this.name,
          domain: this.domain,
          support_email: this.supportEmail,
          conversation_visibility_mode: this.conversationVisibilityMode,
          clear_labels_on_resolved: this.clearLabelsOnResolved,
          resolved_message_enabled: this.resolvedMessageEnabled,
          resolved_message_text: this.resolvedMessageText,
          auto_resolve_inactive_conversations_enabled:
            this.autoResolveInactiveConversationsEnabled,
          auto_resolve_inactive_conversations_minutes:
            Number(this.autoResolveInactiveConversationsMinutes),
          auto_resolve_inactive_conversations_message:
            this.autoResolveInactiveConversationsMessage,
        });
        // If user locale is set, update the locale with user locale
        const updatedLocale = this.uiSettings?.locale || this.locale;
        if (updatedLocale) {
          this.$root.$i18n.locale = updatedLocale;
        }
        this.getAccount(this.id).locale = this.locale;
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.ERROR'));
      }
    },

    async updateConversationVisibilityMode() {
      try {
        await this.$store.dispatch('accounts/update', {
          conversation_visibility_mode: this.conversationVisibilityMode,
          options: { silent: true },
        });
        useAlert(
          this.$t(
            'GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.API.SUCCESS'
          )
        );
      } catch (error) {
        useAlert(
          this.$t(
            'GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.API.ERROR'
          )
        );
      }
    },

    async updateClearLabelsOnResolved() {
      try {
        await this.$store.dispatch('accounts/update', {
          clear_labels_on_resolved: this.clearLabelsOnResolved,
          options: { silent: true },
        });
        useAlert(
          this.$t('GENERAL_SETTINGS.FORM.CLEAR_LABELS_ON_RESOLVED.API.SUCCESS')
        );
      } catch (error) {
        useAlert(
          this.$t('GENERAL_SETTINGS.FORM.CLEAR_LABELS_ON_RESOLVED.API.ERROR')
        );
      }
    },

    async updateResolvedMessageSettings() {
      try {
        await this.$store.dispatch('accounts/update', {
          resolved_message_enabled: this.resolvedMessageEnabled,
          resolved_message_text: this.resolvedMessageText,
          options: { silent: true },
        });
        useAlert(
          this.$t('GENERAL_SETTINGS.FORM.RESOLVED_MESSAGE.API.SUCCESS')
        );
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.RESOLVED_MESSAGE.API.ERROR'));
      }
    },

    async updateAutoResolveInactiveConversationsSettings() {
      try {
        await this.$store.dispatch('accounts/update', {
          auto_resolve_inactive_conversations_enabled:
            this.autoResolveInactiveConversationsEnabled,
          auto_resolve_inactive_conversations_minutes:
            Number(this.autoResolveInactiveConversationsMinutes),
          auto_resolve_inactive_conversations_message:
            this.autoResolveInactiveConversationsMessage,
          options: { silent: true },
        });
        useAlert(
          this.$t(
            'GENERAL_SETTINGS.FORM.AUTO_RESOLVE_INACTIVE_CONVERSATIONS.API.SUCCESS'
          )
        );
      } catch (error) {
        useAlert(
          this.$t(
            'GENERAL_SETTINGS.FORM.AUTO_RESOLVE_INACTIVE_CONVERSATIONS.API.ERROR'
          )
        );
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col w-full max-w-2xl ltr:mr-auto rtl:ml-auto">
    <BaseSettingsHeader :title="$t('GENERAL_SETTINGS.TITLE')" />
    <div class="flex-grow flex-shrink min-w-0 mt-3">
      <SectionLayout
        :title="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.TITLE')"
        :description="$t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.NOTE')"
        class="!pt-0"
      >
        <form
          v-if="!uiFlags.isFetchingItem"
          class="grid gap-4"
          @submit.prevent="updateAccount"
        >
          <WithLabel
            name="account-name"
            :has-error="v$.name.$error"
            :label="$t('GENERAL_SETTINGS.FORM.NAME.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.NAME.ERROR')"
          >
            <NextInput
              v-model="name"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER')"
              @blur="v$.name.$touch"
            />
          </WithLabel>
          <WithLabel
            name="site-language"
            :has-error="v$.locale.$error"
            :label="$t('GENERAL_SETTINGS.FORM.LANGUAGE.LABEL')"
            :error-message="$t('GENERAL_SETTINGS.FORM.LANGUAGE.ERROR')"
          >
            <select v-model="locale" class="!mb-0 text-sm">
              <option
                v-for="lang in languagesSortedByCode"
                :key="lang.iso_639_1_code"
                :value="lang.iso_639_1_code"
              >
                {{ lang.name }}
              </option>
            </select>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyDomainEnabled"
            name="custom-domain"
            :label="$t('GENERAL_SETTINGS.FORM.DOMAIN.LABEL')"
          >
            <NextInput
              v-model="domain"
              type="text"
              class="w-full"
              :placeholder="$t('GENERAL_SETTINGS.FORM.DOMAIN.PLACEHOLDER')"
            />
            <template #help>
              {{
                featureInboundEmailEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED')
              }}

              {{
                featureCustomReplyDomainEnabled &&
                $t('GENERAL_SETTINGS.FORM.FEATURES.CUSTOM_EMAIL_DOMAIN_ENABLED')
              }}
            </template>
          </WithLabel>
          <WithLabel
            v-if="featureCustomReplyEmailEnabled"
            name="support-email"
            :label="$t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.LABEL')"
          >
            <NextInput
              v-model="supportEmail"
              type="text"
              class="w-full"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER')
              "
            />
          </WithLabel>
          <div>
            <NextButton blue :is-loading="isUpdating" type="submit">
              {{ $t('GENERAL_SETTINGS.SUBMIT') }}
            </NextButton>
          </div>
        </form>
      </SectionLayout>

      <woot-loading-state v-if="uiFlags.isFetchingItem" />
    </div>
    <SectionLayout
      v-if="!uiFlags.isFetchingItem"
      :title="$t('GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.TITLE')"
      :description="
        $t('GENERAL_SETTINGS.FORM.CONVERSATION_VISIBILITY_MODE.NOTE')
      "
      with-border
    >
      <fieldset class="grid gap-3">
        <label
          v-for="option in conversationVisibilityOptions"
          :key="option.value"
          class="flex gap-3 p-3 border rounded-lg cursor-pointer border-n-weak hover:border-n-slate-6"
        >
          <input
            v-model="conversationVisibilityMode"
            type="radio"
            name="conversation_visibility_mode"
            class="mt-1"
            :value="option.value"
            @change="updateConversationVisibilityMode"
          />
          <span class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ option.label }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ option.description }}
            </span>
          </span>
        </label>
      </fieldset>
    </SectionLayout>
    <SectionLayout
      v-if="!uiFlags.isFetchingItem"
      :title="$t('GENERAL_SETTINGS.FORM.CLEAR_LABELS_ON_RESOLVED.TITLE')"
      :description="$t('GENERAL_SETTINGS.FORM.CLEAR_LABELS_ON_RESOLVED.NOTE')"
      with-border
    >
      <template #headerActions>
        <div class="flex justify-end">
          <Switch
            v-model="clearLabelsOnResolved"
            @change="updateClearLabelsOnResolved"
          />
        </div>
      </template>
    </SectionLayout>
    <SectionLayout
      v-if="!uiFlags.isFetchingItem"
      :title="$t('GENERAL_SETTINGS.FORM.RESOLVED_MESSAGE.TITLE')"
      :description="$t('GENERAL_SETTINGS.FORM.RESOLVED_MESSAGE.NOTE')"
      with-border
    >
      <template #headerActions>
        <div class="flex justify-end">
          <Switch
            v-model="resolvedMessageEnabled"
            @change="updateResolvedMessageSettings"
          />
        </div>
      </template>
      <WithLabel
        name="resolved-message-text"
        :label="$t('GENERAL_SETTINGS.FORM.RESOLVED_MESSAGE.MESSAGE_LABEL')"
      >
        <textarea
          v-model="resolvedMessageText"
          class="w-full min-h-[160px] text-sm"
          @blur="updateResolvedMessageSettings"
        />
      </WithLabel>
    </SectionLayout>
    <SectionLayout
      v-if="!uiFlags.isFetchingItem"
      :title="
        $t('GENERAL_SETTINGS.FORM.AUTO_RESOLVE_INACTIVE_CONVERSATIONS.TITLE')
      "
      :description="
        $t('GENERAL_SETTINGS.FORM.AUTO_RESOLVE_INACTIVE_CONVERSATIONS.NOTE')
      "
      with-border
    >
      <template #headerActions>
        <div class="flex justify-end">
          <Switch
            v-model="autoResolveInactiveConversationsEnabled"
            @change="updateAutoResolveInactiveConversationsSettings"
          />
        </div>
      </template>
      <div class="grid gap-4">
        <WithLabel
          name="auto-resolve-inactive-conversations-minutes"
          :label="
            $t(
              'GENERAL_SETTINGS.FORM.AUTO_RESOLVE_INACTIVE_CONVERSATIONS.MINUTES_LABEL'
            )
          "
        >
          <NextInput
            v-model.number="autoResolveInactiveConversationsMinutes"
            type="number"
            min="1"
            class="w-full"
            @blur="updateAutoResolveInactiveConversationsSettings"
          />
        </WithLabel>
        <WithLabel
          name="auto-resolve-inactive-conversations-message"
          :label="
            $t(
              'GENERAL_SETTINGS.FORM.AUTO_RESOLVE_INACTIVE_CONVERSATIONS.MESSAGE_LABEL'
            )
          "
        >
          <textarea
            v-model="autoResolveInactiveConversationsMessage"
            class="w-full min-h-[160px] text-sm"
            @blur="updateAutoResolveInactiveConversationsSettings"
          />
        </WithLabel>
      </div>
    </SectionLayout>
    <AudioTranscription v-if="showAudioTranscriptionConfig" />
    <AccountId />
    <div v-if="!uiFlags.isFetchingItem && isOnChatwootCloud">
      <AccountDelete />
    </div>
    <BuildInfo />
  </div>
</template>
