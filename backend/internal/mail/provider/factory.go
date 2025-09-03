package provider

import (
	"fmt"
	"potok/backend/internal/mail/model"
)

// ProviderFactoryImpl implements ProviderFactory
type ProviderFactoryImpl struct{}

// NewProviderFactory creates new provider factory
func NewProviderFactory() *ProviderFactoryImpl {
	return &ProviderFactoryImpl{}
}

// CreateProvider creates email provider based on type
func (f *ProviderFactoryImpl) CreateProvider(providerType model.Provider, config map[string]interface{}) (EmailProvider, error) {
	switch providerType {
	case model.ProviderGmail:
		return NewGmailProvider(config), nil
	case model.ProviderOutlook:
		// TODO: Implement Outlook provider
		return nil, fmt.Errorf("Outlook provider not implemented yet")
	case model.ProviderYandex:
		// TODO: Implement Yandex provider
		return nil, fmt.Errorf("Yandex provider not implemented yet")
	case model.ProviderMailru:
		// TODO: Implement Mail.ru provider
		return nil, fmt.Errorf("Mail.ru provider not implemented yet")
	case model.ProviderIMAP:
		return NewIMAPEmailProvider(config), nil
	default:
		return nil, fmt.Errorf("unsupported provider type: %s", providerType)
	}
}

// SupportsProvider checks if provider type is supported
func (f *ProviderFactoryImpl) SupportsProvider(providerType model.Provider) bool {
	switch providerType {
	case model.ProviderGmail, model.ProviderIMAP:
		return true
	case model.ProviderOutlook, model.ProviderYandex, model.ProviderMailru:
		return false // TODO: Implement these providers
	default:
		return false
	}
}

// GetProviderInfo returns information about supported providers
func (f *ProviderFactoryImpl) GetProviderInfo() map[model.Provider]ProviderInfo {
	return map[model.Provider]ProviderInfo{
		model.ProviderGmail: {
			Name:           "Gmail",
			SupportsOAuth:  true,
			SupportsIMAP:   false,
			MaxMessageSize: 25 * 1024 * 1024, // 25MB
			MaxAttachments: 25,
			SupportedFlags: []string{"seen", "flagged", "answered", "draft", "deleted"},
		},
		model.ProviderOutlook: {
			Name:           "Outlook/Office 365",
			SupportsOAuth:  true,
			SupportsIMAP:   false,
			MaxMessageSize: 35 * 1024 * 1024, // 35MB
			MaxAttachments: 250,
			SupportedFlags: []string{"seen", "flagged", "answered", "draft", "deleted"},
		},
		model.ProviderYandex: {
			Name:           "Яндекс.Почта",
			SupportsOAuth:  true,
			SupportsIMAP:   true,
			MaxMessageSize: 30 * 1024 * 1024, // 30MB
			MaxAttachments: 100,
			SupportedFlags: []string{"seen", "flagged", "answered", "draft", "deleted"},
		},
		model.ProviderMailru: {
			Name:           "Mail.ru",
			SupportsOAuth:  true,
			SupportsIMAP:   true,
			MaxMessageSize: 25 * 1024 * 1024, // 25MB
			MaxAttachments: 100,
			SupportedFlags: []string{"seen", "flagged", "answered", "draft", "deleted"},
		},
		model.ProviderIMAP: {
			Name:           "IMAP/SMTP",
			SupportsOAuth:  false,
			SupportsIMAP:   true,
			MaxMessageSize: 10 * 1024 * 1024, // 10MB (typical)
			MaxAttachments: 10,
			SupportedFlags: []string{"seen", "flagged", "answered", "draft", "deleted"},
		},
	}
}
