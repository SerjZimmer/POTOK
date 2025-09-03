package model

import (
	"time"
)

// Provider represents email provider type
type Provider string

const (
	ProviderGmail   Provider = "gmail"
	ProviderOutlook Provider = "outlook"
	ProviderYandex  Provider = "yandex"
	ProviderMailru  Provider = "mailru"
	ProviderIMAP    Provider = "imap"
)

// MailboxRole represents mailbox role
type MailboxRole string

const (
	MailboxRoleInbox   MailboxRole = "inbox"
	MailboxRoleSent    MailboxRole = "sent"
	MailboxRoleDrafts  MailboxRole = "drafts"
	MailboxRoleSpam    MailboxRole = "spam"
	MailboxRoleTrash   MailboxRole = "trash"
	MailboxRoleArchive MailboxRole = "archive"
	MailboxRoleCustom  MailboxRole = "custom"
)

// MessageFlag represents message flags
type MessageFlag struct {
	Seen     bool `json:"seen"`
	Flagged  bool `json:"flagged"`
	Answered bool `json:"answered"`
}

// ThreadFlags represents thread flags
type ThreadFlags struct {
	Pinned   bool `json:"pinned"`
	Flagged  bool `json:"flagged"`
	Answered bool `json:"answered"`
}

// Account represents mail account
type Account struct {
	UID         string                 `json:"uid"`
	Provider    Provider               `json:"provider"`
	Email       string                 `json:"email"`
	DisplayName *string                `json:"displayName,omitempty"`
	AvatarURL   *string                `json:"avatarUrl,omitempty"`
	IsDefault   bool                   `json:"isDefault"`
	IsVisible   bool                   `json:"isVisible"`
	SyncState   map[string]interface{} `json:"syncState,omitempty"`
	CreatedAt   time.Time              `json:"createdAt"`
	UpdatedAt   time.Time              `json:"updatedAt"`
	DisabledAt  *time.Time             `json:"disabledAt,omitempty"`
}

// AccountUpdate represents account update request
type AccountUpdate struct {
	DisplayName *string                 `json:"displayName,omitempty"`
	IsDefault   *bool                   `json:"isDefault,omitempty"`
	IsVisible   *bool                   `json:"isVisible,omitempty"`
	SyncState   *map[string]interface{} `json:"syncState,omitempty"`
}

// ProviderAuthRequest represents OAuth provider auth request
type ProviderAuthRequest struct {
	Provider    Provider `json:"provider"`
	Email       string   `json:"email"`
	DisplayName *string  `json:"displayName,omitempty"`
}

// ImapAuthRequest represents IMAP auth request
type ImapAuthRequest struct {
	Email       string  `json:"email"`
	DisplayName *string `json:"displayName,omitempty"`
	ImapHost    string  `json:"imapHost"`
	ImapPort    int     `json:"imapPort"`
	ImapTLS     bool    `json:"imapTLS"`
	SmtpHost    string  `json:"smtpHost"`
	SmtpPort    int     `json:"smtpPort"`
	SmtpTLS     bool    `json:"smtpTLS"`
	Username    string  `json:"username"`
	Password    string  `json:"password"`
}

// Mailbox represents email mailbox
type Mailbox struct {
	ID         string      `json:"id"`
	AccountUID string      `json:"accountUid"`
	Name       string      `json:"name"`
	Role       MailboxRole `json:"role"`
	RemoteID   *string     `json:"remoteId,omitempty"`
	Total      int         `json:"total"`
	Unread     int         `json:"unread"`
	Order      int         `json:"order"`
	Visible    bool        `json:"visible"`
}

// Thread represents email thread
type Thread struct {
	ID          string      `json:"id"`
	AccountUID  string      `json:"accountUid"`
	MailboxID   *string     `json:"mailboxId,omitempty"`
	Subject     string      `json:"subject"`
	LastFrom    string      `json:"lastFrom"`
	LastSnippet *string     `json:"lastSnippet,omitempty"`
	LastDate    time.Time   `json:"lastDate"`
	UnreadCount int         `json:"unreadCount"`
	Flags       ThreadFlags `json:"flags"`
	RemoteID    *string     `json:"remoteId,omitempty"`
	Hash        string      `json:"hash"`
}

// ThreadDetail represents thread with messages
type ThreadDetail struct {
	Thread
	Messages []Message `json:"messages"`
}

// Message represents email message
type Message struct {
	ID             string                  `json:"id"`
	ThreadID       string                  `json:"threadId"`
	AccountUID     string                  `json:"accountUid"`
	RemoteID       *string                 `json:"remoteId,omitempty"`
	Headers        map[string]interface{}  `json:"headers,omitempty"`
	From           string                  `json:"from"`
	To             []string                `json:"to"`
	Cc             []string                `json:"cc"`
	Bcc            []string                `json:"bcc"`
	Date           time.Time               `json:"date"`
	Subject        string                  `json:"subject"`
	BodyText       *string                 `json:"bodyText,omitempty"`
	BodyHTML       *string                 `json:"bodyHtml,omitempty"`
	Flags          MessageFlag             `json:"flags"`
	Size           int                     `json:"size"`
	HasAttachments bool                    `json:"hasAttachments"`
	DKIM           *map[string]interface{} `json:"dkim,omitempty"`
	SPF            *map[string]interface{} `json:"spf,omitempty"`
	DMARC          *map[string]interface{} `json:"dmarc,omitempty"`
}

// Attachment represents email attachment
type Attachment struct {
	ID           string     `json:"id"`
	MessageID    string     `json:"messageId"`
	Filename     string     `json:"filename"`
	Mime         string     `json:"mime"`
	Size         int        `json:"size"`
	LocalPath    *string    `json:"localPath,omitempty"`
	RemoteID     *string    `json:"remoteId,omitempty"`
	DownloadedAt *time.Time `json:"downloadedAt,omitempty"`
}

// SendRequest represents send message request
type SendRequest struct {
	AccountUID  string   `json:"accountUid"`
	From        string   `json:"from"`
	To          []string `json:"to"`
	Cc          []string `json:"cc"`
	Bcc         []string `json:"bcc"`
	Subject     string   `json:"subject"`
	BodyText    *string  `json:"bodyText,omitempty"`
	BodyHTML    *string  `json:"bodyHtml,omitempty"`
	Attachments []string `json:"attachments"`
}

// SendResponse represents send message response
type SendResponse struct {
	MessageID     string `json:"messageId"`
	Status        string `json:"status"`
	QueuePosition *int   `json:"queuePosition,omitempty"`
}

// DraftRequest represents draft request
type DraftRequest struct {
	AccountUID  string   `json:"accountUid"`
	From        *string  `json:"from,omitempty"`
	To          []string `json:"to"`
	Cc          []string `json:"cc"`
	Bcc         []string `json:"bcc"`
	Subject     string   `json:"subject"`
	BodyText    *string  `json:"bodyText,omitempty"`
	BodyHTML    *string  `json:"bodyHtml,omitempty"`
	Attachments []string `json:"attachments"`
}

// Draft represents email draft
type Draft struct {
	DraftRequest
	ID        string    `json:"id"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// FlagsUpdate represents flags update request
type FlagsUpdate struct {
	Seen     *bool `json:"seen,omitempty"`
	Flagged  *bool `json:"flagged,omitempty"`
	Answered *bool `json:"answered,omitempty"`
}

// MoveRequest represents move message request
type MoveRequest struct {
	MailboxID string  `json:"mailboxId"`
	RemoteID  *string `json:"remoteId,omitempty"`
}

// OAuthStartRequest represents OAuth start request
type OAuthStartRequest struct {
	Email       string  `json:"email"`
	DisplayName *string `json:"displayName,omitempty"`
}

// OAuthStartResponse represents OAuth start response
type OAuthStartResponse struct {
	AuthURL string `json:"authUrl"`
	State   string `json:"state"`
}

// OAuthCallbackRequest represents OAuth callback request
type OAuthCallbackRequest struct {
	Code  string `json:"code"`
	State string `json:"state"`
}

// OAuthCallbackResponse represents OAuth callback response
type OAuthCallbackResponse struct {
	AccountUID string  `json:"accountUid"`
	Status     string  `json:"status"`
	Error      *string `json:"error,omitempty"`
}

// PageMeta represents pagination metadata
type PageMeta struct {
	Total   int  `json:"total"`
	Page    int  `json:"page"`
	Limit   int  `json:"limit"`
	HasNext bool `json:"hasNext"`
	HasPrev bool `json:"hasPrev"`
}

// Error represents API error response
type Error struct {
	Code    string                  `json:"code"`
	Message string                  `json:"message"`
	Details *map[string]interface{} `json:"details,omitempty"`
}

// ListThreadsParams represents thread listing parameters
type ListThreadsParams struct {
	Mailbox   string
	Query     string
	PageToken string
	Since     *time.Time
	Limit     int
}

// SyncState represents account sync state
type SyncState struct {
	LastSyncAt    time.Time `json:"lastSyncAt"`
	LastMessageID string    `json:"lastMessageId"`
	SyncToken     string    `json:"syncToken"`
	Error         *string   `json:"error,omitempty"`
}
