# == Schema Information
#
# Table name: accounts
#
#  id                    :integer          not null, primary key
#  auto_resolve_duration :integer
#  custom_attributes     :jsonb
#  domain                :string(100)
#  feature_flags         :bigint           default(0), not null
#  internal_attributes   :jsonb            not null
#  limits                :jsonb
#  locale                :integer          default("en")
#  name                  :string           not null
#  settings              :jsonb
#  status                :integer          default("active")
#  support_email         :string(100)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_accounts_on_status  (status)
#

class Account < ApplicationRecord
  # used for single column multi flags
  include FlagShihTzu
  include Reportable
  include Featurable
  include CacheKeys
  include CaptainFeaturable
  include AccountEmailRateLimitable
  include AccountSettingsSchema

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze
  CONVERSATION_VISIBILITY_MODES = {
    default: 0,
    team: 1,
    assignee: 2
  }.freeze
  CONVERSATION_VISIBILITY_MODE_ALIASES = {
    'default' => CONVERSATION_VISIBILITY_MODES[:default],
    'all' => CONVERSATION_VISIBILITY_MODES[:default],
    'team' => CONVERSATION_VISIBILITY_MODES[:team],
    'team_only' => CONVERSATION_VISIBILITY_MODES[:team],
    'assignee' => CONVERSATION_VISIBILITY_MODES[:assignee],
    'assignee_only' => CONVERSATION_VISIBILITY_MODES[:assignee]
  }.freeze
  DEFAULT_RESOLVED_MESSAGE_TEXT = "Agradecemos por entrar em contato conosco 😊\n\n" \
                                  "Permanecemos à disposição para qualquer necessidade futura.\n\n" \
                                  "Desejamos um excelente dia!\n\n" \
                                  "Atenciosamente,\nEquipe {{account.name}}".freeze
  DEFAULT_AUTO_RESOLVE_INACTIVE_CONVERSATIONS_MINUTES = 60
  DEFAULT_AUTO_RESOLVE_INACTIVE_CONVERSATIONS_MESSAGE = "Como não tivemos novas interações, estamos finalizando este atendimento automaticamente. 😊\n\n" \
                                                       "Caso precise de algo, basta enviar uma nova mensagem.\n\n" \
                                                       "Atenciosamente,\nEquipe {{account.name}}".freeze

  DEFAULT_AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_INTERVAL_MINUTES = 15
  DEFAULT_AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_BATCH_LIMIT = 100

  validates :name, presence: true
  # `domain` is the inbound email domain used to construct reply addresses
  # (see `inbound_email_domain`). Do not repurpose it for a website or any
  # non-mail-related domain.
  validates :domain, length: { maximum: 100 }
  validates_with JsonSchemaValidator,
                 schema: SETTINGS_PARAMS_SCHEMA,
                 attribute_resolver: ->(record) { record.settings }
  validate :validate_reporting_timezone
  validate :validate_support_email_format, if: :will_save_change_to_support_email?

  store_accessor :settings, :auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting

  store_accessor :settings, :audio_transcriptions, :auto_resolve_label
  store_accessor :settings, :conversation_visibility_mode
  store_accessor :settings, :clear_labels_on_resolved
  store_accessor :settings, :resolved_message_enabled, :resolved_message_text
  store_accessor :settings, :auto_resolve_inactive_conversations_enabled, :auto_resolve_inactive_conversations_minutes
  store_accessor :settings, :auto_resolve_inactive_conversations_message
  store_accessor :settings, :auto_assign_unassigned_team_conversations_enabled
  store_accessor :settings, :auto_assign_unassigned_team_conversations_interval_minutes
  store_accessor :settings, :auto_assign_unassigned_team_conversations_online_only
  store_accessor :settings, :auto_assign_unassigned_team_conversations_batch_limit
  store_accessor :settings, :captain_models, :captain_features
  store_accessor :settings, :reporting_timezone
  store_accessor :settings, :keep_pending_on_bot_failure
  store_accessor :settings, :captain_auto_resolve_mode, :captain_false_promise_harness_enabled
  include AccountCaptainAutoResolve

  has_many :account_users, dependent: :destroy_async
  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :agent_bots, dependent: :destroy_async
  has_many :api_channels, dependent: :destroy_async, class_name: '::Channel::Api'
  has_many :articles, dependent: :destroy_async, class_name: '::Article'
  has_many :assignment_policies, dependent: :destroy_async
  has_many :automation_rules, dependent: :destroy_async
  has_many :macros, dependent: :destroy_async
  has_many :campaigns, dependent: :destroy_async
  has_many :canned_responses, dependent: :destroy_async
  has_many :categories, dependent: :destroy_async, class_name: '::Category'
  has_many :contacts, dependent: :destroy_async
  has_many :conversations, dependent: :destroy_async
  has_many :csat_survey_responses, dependent: :destroy_async
  has_many :custom_attribute_definitions, dependent: :destroy_async
  has_many :custom_filters, dependent: :destroy_async
  has_many :dashboard_apps, dependent: :destroy_async
  has_many :data_imports, dependent: :destroy_async
  has_many :email_channels, dependent: :destroy_async, class_name: '::Channel::Email'
  has_many :facebook_pages, dependent: :destroy_async, class_name: '::Channel::FacebookPage'
  has_many :instagram_channels, dependent: :destroy_async, class_name: '::Channel::Instagram'
  has_many :tiktok_channels, dependent: :destroy_async, class_name: '::Channel::Tiktok'
  has_many :hooks, dependent: :destroy_async, class_name: 'Integrations::Hook'
  has_many :inboxes, dependent: :destroy_async
  has_many :labels, dependent: :destroy_async
  has_many :line_channels, dependent: :destroy_async, class_name: '::Channel::Line'
  has_many :mentions, dependent: :destroy_async
  has_many :messages, dependent: :destroy_async
  has_many :notes, dependent: :destroy_async
  has_many :notification_settings, dependent: :destroy_async
  has_many :notifications, dependent: :destroy_async
  has_many :portals, dependent: :destroy_async, class_name: '::Portal'
  has_many :sms_channels, dependent: :destroy_async, class_name: '::Channel::Sms'
  has_many :teams, dependent: :destroy_async
  has_many :telegram_channels, dependent: :destroy_async, class_name: '::Channel::Telegram'
  has_many :twilio_sms, dependent: :destroy_async, class_name: '::Channel::TwilioSms'
  has_many :twitter_profiles, dependent: :destroy_async, class_name: '::Channel::TwitterProfile'
  has_many :users, through: :account_users
  has_many :web_widgets, dependent: :destroy_async, class_name: '::Channel::WebWidget'
  has_many :webhooks, dependent: :destroy_async
  has_many :whatsapp_channels, dependent: :destroy_async, class_name: '::Channel::Whatsapp'
  has_many :working_hours, dependent: :destroy_async

  has_one_attached :contacts_export

  enum :locale, LANGUAGES_CONFIG.map { |key, val| [val[:iso_639_1_code], key] }.to_h, prefix: true
  enum :status, { active: 0, suspended: 1 }

  scope :with_auto_resolve, -> { where("(settings ->> 'auto_resolve_after')::int IS NOT NULL") }
  scope :with_inactive_conversation_auto_resolve, lambda {
    left_joins(:inboxes)
      .where("(settings ->> 'auto_resolve_inactive_conversations_enabled') = 'true' OR inboxes.auto_resolve_inactive_conversations_enabled = TRUE")
      .distinct
  }
  scope :with_auto_assign_unassigned_team_conversations, lambda {
    where("(settings ->> 'auto_assign_unassigned_team_conversations_enabled') = 'true'")
  }

  before_validation :validate_limit_keys
  before_validation :normalize_conversation_visibility_mode
  after_create_commit :notify_creation
  after_update_commit :clear_unread_conversation_counts_cache, if: :saved_change_to_feature_conversation_unread_counts?
  after_destroy :remove_account_sequences

  def agents
    users.where(account_users: { role: :agent })
  end

  def administrators
    users.where(account_users: { role: :administrator })
  end

  def all_conversation_tags
    # returns array of tags
    conversation_ids = conversations.pluck(:id)
    ActsAsTaggableOn::Tagging.includes(:tag)
                             .where(context: 'labels',
                                    taggable_type: 'Conversation',
                                    taggable_id: conversation_ids)
                             .map { |tagging| tagging.tag.name }
  end

  def webhook_data
    {
      id: id,
      name: name
    }
  end

  def inbound_email_domain
    domain.presence || GlobalConfig.get('MAILER_INBOUND_EMAIL_DOMAIN')['MAILER_INBOUND_EMAIL_DOMAIN'] || ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN',
                                                                                                                   false)
  end

  def support_email
    super.presence || ENV.fetch('MAILER_SENDER_EMAIL') { GlobalConfig.get('MAILER_SUPPORT_EMAIL')['MAILER_SUPPORT_EMAIL'] }
  end

  def usage_limits
    {
      agents: ChatwootApp.max_limit.to_i,
      inboxes: ChatwootApp.max_limit.to_i
    }
  end

  def conversation_visibility_mode
    raw_mode = settings&.fetch('conversation_visibility_mode', nil)
    normalized_mode = normalize_conversation_visibility_value(raw_mode)
    return normalized_mode unless normalized_mode.nil?

    return CONVERSATION_VISIBILITY_MODES[:assignee] if settings_boolean('restrict_conversations_to_assignee')
    return CONVERSATION_VISIBILITY_MODES[:team] if settings_boolean('restrict_conversations_by_team')

    CONVERSATION_VISIBILITY_MODES[:default]
  end

  def conversation_visibility_mode=(value)
    self.settings ||= {}
    settings['conversation_visibility_mode'] = normalize_conversation_visibility_value(value)
  end

  def clear_labels_on_resolved?
    ActiveModel::Type::Boolean.new.cast(clear_labels_on_resolved)
  end

  def resolved_message_enabled?
    ActiveModel::Type::Boolean.new.cast(resolved_message_enabled)
  end

  def resolved_message_text
    settings_value_or_default('resolved_message_text', DEFAULT_RESOLVED_MESSAGE_TEXT)
  end

  def auto_resolve_inactive_conversations_enabled?
    ActiveModel::Type::Boolean.new.cast(auto_resolve_inactive_conversations_enabled)
  end

  def auto_resolve_inactive_conversations_minutes
    settings_value_or_default(
      'auto_resolve_inactive_conversations_minutes',
      DEFAULT_AUTO_RESOLVE_INACTIVE_CONVERSATIONS_MINUTES
    ).to_i
  end

  def auto_resolve_inactive_conversations_message
    settings_value_or_default(
      'auto_resolve_inactive_conversations_message',
      DEFAULT_AUTO_RESOLVE_INACTIVE_CONVERSATIONS_MESSAGE
    )
  end

  def auto_assign_unassigned_team_conversations_enabled?
    ActiveModel::Type::Boolean.new.cast(auto_assign_unassigned_team_conversations_enabled)
  end

  def auto_assign_unassigned_team_conversations_online_only?
    value = settings_value_or_default('auto_assign_unassigned_team_conversations_online_only', true)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def auto_assign_unassigned_team_conversations_interval_minutes
    value = settings_value_or_default(
      'auto_assign_unassigned_team_conversations_interval_minutes',
      DEFAULT_AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_INTERVAL_MINUTES
    ).to_i
    value.positive? ? value : DEFAULT_AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_INTERVAL_MINUTES
  end

  def auto_assign_unassigned_team_conversations_batch_limit
    value = settings_value_or_default(
      'auto_assign_unassigned_team_conversations_batch_limit',
      DEFAULT_AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_BATCH_LIMIT
    ).to_i
    value.positive? ? value : DEFAULT_AUTO_ASSIGN_UNASSIGNED_TEAM_CONVERSATIONS_BATCH_LIMIT
  end

  def locale_english_name
    # the locale can also be something like pt_BR, en_US, fr_FR, etc.
    # the format is `<locale_code>_<country_code>`
    # we need to extract the language code from the locale
    account_locale = locale&.split('_')&.first
    ISO_639.find(account_locale)&.english_name&.downcase || 'english'
  end

  def onboarding_step
    step = custom_attributes['onboarding_step']
    return nil if step.blank?

    enrichment_key = format(Redis::Alfred::ACCOUNT_ONBOARDING_ENRICHMENT, account_id: id)
    Redis::Alfred.exists?(enrichment_key) ? 'enrichment' : step
  end

  def reset_cache_keys
    super
    clear_unread_conversation_counts_cache
  end

  private

  def notify_creation
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CREATED, Time.zone.now, account: self)
  end

  def clear_unread_conversation_counts_cache
    ::Conversations::UnreadCounts::Store.clear_account!(id)
  end

  def settings_boolean(key)
    ActiveModel::Type::Boolean.new.cast(settings&.fetch(key, nil))
  end

  def settings_value_or_default(key, default_value)
    return default_value unless settings&.key?(key)

    settings[key]
  end

  def normalize_conversation_visibility_mode
    return unless settings.is_a?(Hash)

    settings['conversation_visibility_mode'] = conversation_visibility_mode
  end

  def normalize_conversation_visibility_value(value)
    return nil if value.blank? && value != 0

    return value if CONVERSATION_VISIBILITY_MODES.value?(value)
    return value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/) && CONVERSATION_VISIBILITY_MODES.value?(value.to_i)

    CONVERSATION_VISIBILITY_MODE_ALIASES[value.to_s]
  end

  trigger.after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  trigger.name('camp_dpid_before_insert').after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  def validate_limit_keys
    # method overridden in enterprise module
  end

  def validate_reporting_timezone
    return if reporting_timezone.blank? || ActiveSupport::TimeZone[reporting_timezone].present?

    errors.add(:reporting_timezone, I18n.t('errors.account.reporting_timezone.invalid'))
  end

  def validate_support_email_format
    value = attributes['support_email']
    return if value.blank?

    parsed = Mail::Address.new(value).address
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid')) if parsed.blank?
  rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid'))
  end

  def remove_account_sequences
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS camp_dpid_seq_#{id}")
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS conv_dpid_seq_#{id}")
  end
end

Account.prepend_mod_with('Account')
Account.prepend_mod_with('Account::PlanUsageAndLimits')
Account.include_mod_with('Concerns::Account')
Account.include_mod_with('Audit::Account')
