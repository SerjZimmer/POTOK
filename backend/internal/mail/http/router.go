package http

import (
	"encoding/json"
	"net/http"
	"strconv"

	"potok/backend/internal/mail/model"
	"potok/backend/internal/mail/service"

	"github.com/go-chi/chi/v5"
)

// Router handles HTTP requests for mail module
type Router struct {
	accountService service.AccountService
	threadService  service.ThreadService
	sendService    service.SendService
}

// NewRouter creates new mail router
func NewRouter(
	accountService service.AccountService,
	threadService service.ThreadService,
	sendService service.SendService,
) http.Handler {
	r := chi.NewRouter()

	api := &Router{
		accountService: accountService,
		threadService:  threadService,
		sendService:    sendService,
	}

	// Mount routes
	r.Route("/v1", func(r chi.Router) {
		// Accounts
		r.Route("/mail/accounts", func(r chi.Router) {
			r.Get("/", api.listAccounts)
			r.Post("/", api.createAccount)
			r.Route("/{accountUid}", func(r chi.Router) {
				r.Get("/", api.getAccount)
				r.Patch("/", api.updateAccount)
				r.Delete("/", api.deleteAccount)
				r.Get("/mailboxes", api.listAccountMailboxes)
				r.Get("/threads", api.listAccountThreads)
			})
		})

		// Threads
		r.Route("/mail/threads", func(r chi.Router) {
			r.Get("/{threadId}", api.getThread)
		})

		// Messages
		r.Route("/mail/messages", func(r chi.Router) {
			r.Get("/{messageId}", api.getMessage)
			r.Route("/{messageId}", func(r chi.Router) {
				r.Post("/flags", api.setMessageFlags)
				r.Post("/move", api.moveMessage)
				r.Delete("/", api.deleteMessage)
				r.Delete("/permanent", api.deleteMessagePermanent)
			})
		})

		// Attachments
		r.Route("/mail/messages/{messageId}/attachments", func(r chi.Router) {
			r.Get("/{attachmentId}", api.downloadAttachment)
		})

		// Send
		r.Route("/mail", func(r chi.Router) {
			r.Post("/send", api.sendMessage)
			r.Post("/drafts", api.createDraft)
		})

		// OAuth
		r.Route("/mail/oauth/{provider}", func(r chi.Router) {
			r.Post("/start", api.startOAuth)
			r.Post("/callback", api.completeOAuth)
		})
	})

	return r
}

// --- Account handlers ---

func (rt *Router) listAccounts(w http.ResponseWriter, r *http.Request) {
	includeDisabled := r.URL.Query().Get("include_disabled") == "true"

	accounts, err := rt.accountService.ListAccounts(r.Context(), includeDisabled)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to list accounts", err)
		return
	}

	respondWithJSON(w, http.StatusOK, map[string]interface{}{
		"items": accounts,
		"meta": model.PageMeta{
			Total:   len(accounts),
			Page:    1,
			Limit:   len(accounts),
			HasNext: false,
			HasPrev: false,
		},
	})
}

func (rt *Router) createAccount(w http.ResponseWriter, r *http.Request) {
	var req interface{}

	// Try to parse as OAuth request first
	var oauthReq model.ProviderAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&oauthReq); err == nil && oauthReq.Provider != "" {
		req = oauthReq
	} else {
		// Try to parse as IMAP request
		var imapReq model.ImapAuthRequest
		if err := json.NewDecoder(r.Body).Decode(&imapReq); err != nil {
			respondWithError(w, http.StatusBadRequest, "Invalid request format", err)
			return
		}
		req = imapReq
	}

	account, err := rt.accountService.CreateAccount(r.Context(), req)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Failed to create account", err)
		return
	}

	respondWithJSON(w, http.StatusCreated, account)
}

func (rt *Router) getAccount(w http.ResponseWriter, r *http.Request) {
	accountUID := chi.URLParam(r, "accountUid")

	account, err := rt.accountService.GetAccount(r.Context(), accountUID)
	if err != nil {
		respondWithError(w, http.StatusNotFound, "Account not found", err)
		return
	}

	respondWithJSON(w, http.StatusOK, account)
}

func (rt *Router) updateAccount(w http.ResponseWriter, r *http.Request) {
	accountUID := chi.URLParam(r, "accountUid")

	var update model.AccountUpdate
	if err := json.NewDecoder(r.Body).Decode(&update); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request format", err)
		return
	}

	account, err := rt.accountService.UpdateAccount(r.Context(), accountUID, update)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to update account", err)
		return
	}

	respondWithJSON(w, http.StatusOK, account)
}

func (rt *Router) deleteAccount(w http.ResponseWriter, r *http.Request) {
	accountUID := chi.URLParam(r, "accountUid")

	if err := rt.accountService.DeleteAccount(r.Context(), accountUID); err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to delete account", err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (rt *Router) listAccountMailboxes(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement mailbox listing
	respondWithJSON(w, http.StatusOK, map[string]interface{}{
		"items": []model.Mailbox{},
		"meta": model.PageMeta{
			Total:   0,
			Page:    1,
			Limit:   0,
			HasNext: false,
			HasPrev: false,
		},
	})
}

func (rt *Router) listAccountThreads(w http.ResponseWriter, r *http.Request) {
	accountUID := chi.URLParam(r, "accountUid")

	// Parse query parameters
	mailbox := r.URL.Query().Get("mailbox")
	if mailbox == "" {
		mailbox = "INBOX"
	}

	query := r.URL.Query().Get("q")
	pageToken := r.URL.Query().Get("pageToken")

	limitStr := r.URL.Query().Get("limit")
	limit := 50
	if limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 100 {
			limit = l
		}
	}

	params := model.ListThreadsParams{
		Mailbox:   mailbox,
		Query:     query,
		PageToken: pageToken,
		Limit:     limit,
	}

	threads, nextToken, err := rt.threadService.ListThreads(r.Context(), accountUID, params)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to list threads", err)
		return
	}

	respondWithJSON(w, http.StatusOK, map[string]interface{}{
		"items":         threads,
		"nextPageToken": nextToken,
		"meta": model.PageMeta{
			Total:   len(threads),
			Page:    1,
			Limit:   limit,
			HasNext: nextToken != "",
			HasPrev: false,
		},
	})
}

// --- Thread handlers ---

func (rt *Router) getThread(w http.ResponseWriter, r *http.Request) {
	threadID := chi.URLParam(r, "threadId")

	thread, err := rt.threadService.GetThread(r.Context(), threadID)
	if err != nil {
		respondWithError(w, http.StatusNotFound, "Thread not found", err)
		return
	}

	respondWithJSON(w, http.StatusOK, thread)
}

// --- Message handlers ---

func (rt *Router) getMessage(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement message retrieval
	respondWithError(w, http.StatusNotImplemented, "Message retrieval not implemented yet", nil)
}

func (rt *Router) setMessageFlags(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement flag setting
	respondWithError(w, http.StatusNotImplemented, "Flag setting not implemented yet", nil)
}

func (rt *Router) moveMessage(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement message moving
	respondWithError(w, http.StatusNotImplemented, "Message moving not implemented yet", nil)
}

func (rt *Router) deleteMessage(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement message deletion
	respondWithError(w, http.StatusNotImplemented, "Message deletion not implemented yet", nil)
}

func (rt *Router) deleteMessagePermanent(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement permanent deletion
	respondWithError(w, http.StatusNotImplemented, "Permanent deletion not implemented yet", nil)
}

// --- Attachment handlers ---

func (rt *Router) downloadAttachment(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement attachment download
	respondWithError(w, http.StatusNotImplemented, "Attachment download not implemented yet", nil)
}

// --- Send handlers ---

func (rt *Router) sendMessage(w http.ResponseWriter, r *http.Request) {
	var req model.SendRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request format", err)
		return
	}

	response, err := rt.sendService.SendMessage(r.Context(), req)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Failed to send message", err)
		return
	}

	respondWithJSON(w, http.StatusAccepted, response)
}

func (rt *Router) createDraft(w http.ResponseWriter, r *http.Request) {
	// TODO: Implement draft creation
	respondWithError(w, http.StatusNotImplemented, "Draft creation not implemented yet", nil)
}

// --- OAuth handlers ---

func (rt *Router) startOAuth(w http.ResponseWriter, r *http.Request) {
	provider := model.Provider(chi.URLParam(r, "provider"))

	var req model.OAuthStartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request format", err)
		return
	}

	authURL, state, err := rt.accountService.StartOAuth(r.Context(), provider, req.Email)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to start OAuth", err)
		return
	}

	respondWithJSON(w, http.StatusOK, model.OAuthStartResponse{
		AuthURL: authURL,
		State:   state,
	})
}

func (rt *Router) completeOAuth(w http.ResponseWriter, r *http.Request) {
	provider := model.Provider(chi.URLParam(r, "provider"))

	var req model.OAuthCallbackRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request format", err)
		return
	}

	account, err := rt.accountService.CompleteOAuth(r.Context(), provider, req.Code, req.State)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to complete OAuth", err)
		return
	}

	respondWithJSON(w, http.StatusOK, model.OAuthCallbackResponse{
		AccountUID: account.UID,
		Status:     "success",
	})
}

// --- Helper functions ---

func respondWithJSON(w http.ResponseWriter, statusCode int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	if data != nil {
		if err := json.NewEncoder(w).Encode(data); err != nil {
			http.Error(w, "Failed to encode response", http.StatusInternalServerError)
		}
	}
}

func respondWithError(w http.ResponseWriter, statusCode int, message string, err error) {
	errorResponse := model.Error{
		Code:    "internal_error",
		Message: message,
	}

	if err != nil {
		details := map[string]interface{}{
			"error": err.Error(),
		}
		errorResponse.Details = &details
	}

	respondWithJSON(w, statusCode, errorResponse)
}
