package provider

import (
	"context"
	"potok/backend/internal/mail/model"
)

// EmailProvider defines interface for email providers
type EmailProvider interface {
	// Authentication
	Authenticate(ctx context.Context, credentials interface{}) error
	ValidateCredentials(ctx context.Context) error

	// Mailbox operations
	ListMailboxes(ctx context.Context) ([]model.Mailbox, error)
	GetMailbox(ctx context.Context, mailboxID string) (*model.Mailbox, error)

	// Thread operations
	ListThreads(ctx context.Context, params model.ListThreadsParams) ([]model.Thread, string, error)
	GetThread(ctx context.Context, threadID string) (*model.ThreadDetail, error)

	// Message operations
	GetMessage(ctx context.Context, messageID string) (*model.Message, error)
	FetchMessageBody(ctx context.Context, messageID string) (*model.Message, error)
	SetFlags(ctx context.Context, messageID string, flags model.MessageFlag) error
	MoveMessage(ctx context.Context, messageID string, mailboxID string) error
	DeleteMessage(ctx context.Context, messageID string, permanent bool) error

	// Attachment operations
	DownloadAttachment(ctx context.Context, messageID string, attachmentID string) ([]byte, error)

	// Sending operations
	SendMessage(ctx context.Context, req model.SendRequest) error
	SaveDraft(ctx context.Context, draft model.DraftRequest) (*model.Draft, error)

	// Sync operations
	GetSyncState(ctx context.Context) (*model.SyncState, error)
	UpdateSyncState(ctx context.Context, state model.SyncState) error

	// Provider info
	GetProviderInfo() ProviderInfo
}

// ProviderInfo contains provider-specific information
type ProviderInfo struct {
	Name           string
	SupportsOAuth  bool
	SupportsIMAP   bool
	MaxMessageSize int64
	MaxAttachments int
	SupportedFlags []string
}

// ProviderFactory creates email providers
type ProviderFactory interface {
	CreateProvider(providerType model.Provider, config map[string]interface{}) (EmailProvider, error)
	SupportsProvider(providerType model.Provider) bool
}

// OAuthProvider defines interface for OAuth-enabled providers
type OAuthProvider interface {
	EmailProvider
	StartOAuth(ctx context.Context, email string) (string, string, error) // returns authURL, state
	CompleteOAuth(ctx context.Context, code string, state string) (*model.Account, error)
	RefreshToken(ctx context.Context) error
}

// IMAPProvider defines interface for IMAP-based providers
type IMAPProvider interface {
	EmailProvider
	TestConnection(ctx context.Context) error
	GetConnectionInfo() IMAPConnectionInfo
}

// IMAPConnectionInfo contains IMAP connection details
type IMAPConnectionInfo struct {
	ImapHost string
	ImapPort int
	ImapTLS  bool
	SmtpHost string
	SmtpPort int
	SmtpTLS  bool
	Username string
}

// ProviderError represents provider-specific errors
type ProviderError struct {
	Code    string
	Message string
	Details map[string]interface{}
}

func (e ProviderError) Error() string {
	return e.Message
}

// Common provider error codes
const (
	ErrCodeAuthFailed       = "auth_failed"
	ErrCodeConnectionFailed = "connection_failed"
	ErrCodeRateLimited      = "rate_limited"
	ErrCodeQuotaExceeded    = "quota_exceeded"
	ErrCodeMessageNotFound  = "message_not_found"
	ErrCodeInvalidRequest   = "invalid_request"
	ErrCodeServerError      = "server_error"
)
