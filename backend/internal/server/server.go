package server

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/gorilla/mux"
	"potok/backend/internal/store"
)

// Server содержит зависимости для HTTP-сервера, такие как роутер и хранилище.
type Server struct {
	router *mux.Router
	store  *store.Store
}

// New создает новый экземпляр Server.
func New(store *store.Store) *Server {
	s := &Server{store: store, router: mux.NewRouter()}
	s.configureRoutes()
	return s
}

// ServeHTTP делает Server совместимым с интерфейсом http.Handler.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.router.ServeHTTP(w, r)
}

// configureRoutes настраивает все маршруты для API.
func (s *Server) configureRoutes() {
	// Маршруты для Папок
	s.router.HandleFunc("/folders", s.handleGetFolders()).Methods("GET")
	s.router.HandleFunc("/folders", s.handleCreateFolder()).Methods("POST")
	s.router.HandleFunc("/folders/{folderId}", s.handleDeleteFolder()).Methods("DELETE") // New route

	// Маршруты для Заметок
	s.router.HandleFunc("/folders/{folderId}/notes", s.handleListNotes()).Methods("GET")
	s.router.HandleFunc("/notes", s.handleListAllNotes()).Methods("GET") // New route
	s.router.HandleFunc("/notes", s.handleCreateNote()).Methods("POST")
	s.router.HandleFunc("/notes/{noteId}", s.handleUpdateNote()).Methods("PUT")
	s.router.HandleFunc("/notes/{noteId}", s.handleDeleteNote()).Methods("DELETE")
}

// New handler to delete a folder and its notes
func (s *Server) handleDeleteFolder() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		folderId := vars["folderId"]

		slog.Info("Запрос на удаление папки и её заметок",
			"path", r.URL.Path, "method", r.Method, "folder_id", folderId)

		if err := s.store.DeleteFolderWithNotes(folderId); err != nil {
			slog.Error("Не удалось удалить папку и заметки",
				"path", r.URL.Path, "method", r.Method, "folder_id", folderId, "error", err)
			respondWithError(w, http.StatusInternalServerError, "Не удалось удалить папку и заметки")
			return
		}

		slog.Info("Папка и связанные заметки удалены",
			"path", r.URL.Path, "method", r.Method, "folder_id", folderId)
		respondWithJSON(w, http.StatusNoContent, nil)
	}
}

// New handler to list all notes
func (s *Server) handleListAllNotes() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		slog.Info("Запрос списка всех заметок",
			"path", r.URL.Path, "method", r.Method)

		sortBy := r.URL.Query().Get("sort_by") // Get sort_by query parameter
		notes, err := s.store.ListAllNotes(sortBy) // Pass sortBy to store method
		if err != nil {
			slog.Error("Не удалось получить все заметки",
				"path", r.URL.Path, "method", r.Method, "error", err)
			respondWithError(w, http.StatusInternalServerError, "Не удалось получить все заметки")
			return
		}

		slog.Info("Список всех заметок получен",
			"path", r.URL.Path, "method", r.Method, "count", len(notes))
		respondWithJSON(w, http.StatusOK, notes)
	}
}

// --- Обработчики ---

func (s *Server) handleGetFolders() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		slog.Info("Запрос списка папок",
			"path", r.URL.Path, "method", r.Method)

		folders, err := s.store.GetFolders()
		if err != nil {
			slog.Error("Не удалось получить папки",
				"path", r.URL.Path, "method", r.Method, "error", err)
			respondWithError(w, http.StatusInternalServerError, "Не удалось получить папки")
			return
		}

		slog.Info("Список папок получен",
			"path", r.URL.Path, "method", r.Method, "count", len(folders))
		respondWithJSON(w, http.StatusOK, folders)
	}
}

func (s *Server) handleCreateFolder() http.HandlerFunc {
	type request struct {
		Name string `json:"name"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		slog.Info("Запрос на создание папки",
			"path", r.URL.Path, "method", r.Method)

		var req request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			slog.Warn("Неверный запрос при создании папки: ошибка декодирования тела",
				"path", r.URL.Path, "method", r.Method, "error", err)
			respondWithError(w, http.StatusBadRequest, "Неверный запрос")
			return
		}

		folder, err := s.store.CreateFolder(req.Name)
		if err != nil {
			slog.Error("Не удалось создать папку",
				"path", r.URL.Path, "method", r.Method, "name", req.Name, "error", err)
			respondWithError(w, http.StatusInternalServerError, "Не удалось создать папку")
			return
		}

		slog.Info("Папка создана",
			"path", r.URL.Path, "method", r.Method, "folder_id", folder.ID, "name", folder.Name)
		respondWithJSON(w, http.StatusCreated, folder)
	}
}

func (s *Server) handleListNotes() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		folderId := vars["folderId"]
		sortBy := r.URL.Query().Get("sort_by") // Get sort_by query parameter

		slog.Info("Запрос списка заметок в папке",
			"path", r.URL.Path, "method", r.Method, "folder_id", folderId, "sort_by", sortBy)

		notes, err := s.store.ListNotes(folderId, sortBy) // Pass sortBy to store method
		if err != nil {
			slog.Error("Не удалось получить заметки папки",
				"path", r.URL.Path, "method", r.Method, "folder_id", folderId, "error", err)
			respondWithError(w, http.StatusInternalServerError, "Не удалось получить заметки")
			return
		}

		slog.Info("Список заметок получен",
			"path", r.URL.Path, "method", r.Method, "folder_id", folderId, "count", len(notes))
		respondWithJSON(w, http.StatusOK, notes)
	}
}

func (s *Server) handleCreateNote() http.HandlerFunc {
	type request struct {
		Title    string `json:"title"`
		Content  string `json:"content"`
		FolderID string `json:"folder_id"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		slog.Info("Запрос на создание заметки",
			"path", r.URL.Path, "method", r.Method)

		var req request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			slog.Warn("Неверный запрос при создании заметки: ошибка декодирования тела",
				"path", r.URL.Path, "method", r.Method, "error", err)
			respondWithError(w, http.StatusBadRequest, "Неверный запрос")
			return
		}

		note, err := s.store.CreateNote(req.Title, req.Content, req.FolderID)
		if err != nil {
			slog.Error("Не удалось создать заметку",
				"path", r.URL.Path, "method", r.Method, "folder_id", req.FolderID, "error", err)
			respondWithError(w, http.StatusInternalServerError, "Не удалось создать заметку")
			return
		}

		slog.Info("Заметка создана",
			"path", r.URL.Path, "method", r.Method, "note_id", note.ID, "folder_id", note.FolderID)
		respondWithJSON(w, http.StatusCreated, note)
	}
}

func (s *Server) handleUpdateNote() http.HandlerFunc {
	type request struct {
		Title    string `json:"title"`
		Content  string `json:"content"`
		FolderID string `json:"folder_id"` // Added FolderID
	}
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		noteId := vars["noteId"]

		slog.Info("Запрос на обновление заметки",
			"path", r.URL.Path, "method", r.Method, "note_id", noteId)

		var req request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			slog.Warn("Неверный запрос при обновлении заметки: ошибка декодирования тела",
				"path", r.URL.Path, "method", r.Method, "note_id", noteId, "error", err)
			respondWithError(w, http.StatusBadRequest, "Неверный запрос")
			return
		}

		note, err := s.store.UpdateNote(noteId, req.Title, req.Content, req.FolderID) // Pass FolderID
		if err != nil {
			slog.Error("Не удалось обновить заметку",
				"path", r.URL.Path, "method", r.Method, "note_id", noteId, "error", err)
			respondWithError(w, http.StatusInternalServerError, "Не удалось обновить заметку")
			return
		}

		slog.Info("Заметка обновлена",
			"path", r.URL.Path, "method", r.Method, "note_id", note.ID, "folder_id", note.FolderID)
		respondWithJSON(w, http.StatusOK, note)
	}
}

func (s *Server) handleDeleteNote() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		noteId := vars["noteId"]

		slog.Info("Запрос на удаление заметки",
			"path", r.URL.Path, "method", r.Method, "note_id", noteId)

		if err := s.store.DeleteNote(noteId); err != nil {
			slog.Error("Не удалось удалить заметку",
				"path", r.URL.Path, "method", r.Method, "note_id", noteId, "error", err)
			respondWithError(w, http.StatusInternalServerError, "Не удалось удалить заметку")
			return
		}

		slog.Info("Заметка удалена",
			"path", r.URL.Path, "method", r.Method, "note_id", noteId)
		respondWithJSON(w, http.StatusNoContent, nil)
	}
}

// --- Вспомогательные функции ---

func respondWithError(w http.ResponseWriter, code int, message string) {
	slog.Error("Ошибка ответа клиенту", "http_status", code, "сообщение", message)
	respondWithJSON(w, code, map[string]string{"error": message})
}

func respondWithJSON(w http.ResponseWriter, code int, payload interface{}) {
	var response []byte
	var err error

	if payload != nil {
		response, err = json.Marshal(payload)
		if err != nil {
			slog.Error("Не удалось сериализовать ответ", "error", err)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"error":"Внутренняя ошибка сервера"}`))
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if payload != nil {
		_, _ = w.Write(response)
		slog.Info("Ответ отправлен", "http_status", code, "bytes", len(response))
		return
	}
	// Для 204/пустого payload — просто логируем факт отправки без тела
	slog.Info("Ответ отправлен (без тела)", "http_status", code)
}
