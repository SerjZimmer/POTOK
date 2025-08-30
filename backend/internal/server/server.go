package server

import (
	"encoding/json"
	"log"
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

		if err := s.store.DeleteFolderWithNotes(folderId); err != nil {
			respondWithError(w, http.StatusInternalServerError, "Не удалось удалить папку и заметки")
			return
		}
		respondWithJSON(w, http.StatusNoContent, nil)
	}
}

// New handler to list all notes
func (s *Server) handleListAllNotes() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		notes, err := s.store.ListAllNotes() // New store method
		if err != nil {
			respondWithError(w, http.StatusInternalServerError, "Не удалось получить все заметки")
			return
		}
		respondWithJSON(w, http.StatusOK, notes)
	}
}

// --- Обработчики ---

func (s *Server) handleGetFolders() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		folders, err := s.store.GetFolders()
		if err != nil {
			respondWithError(w, http.StatusInternalServerError, "Не удалось получить папки")
			return
		}
		respondWithJSON(w, http.StatusOK, folders)
	}
}

func (s *Server) handleCreateFolder() http.HandlerFunc {
	type request struct {
		Name string `json:"name"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		var req request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			respondWithError(w, http.StatusBadRequest, "Неверный запрос")
			return
		}

		folder, err := s.store.CreateFolder(req.Name)
		if err != nil {
			respondWithError(w, http.StatusInternalServerError, "Не удалось создать папку")
			return
		}
		respondWithJSON(w, http.StatusCreated, folder)
	}
}

func (s *Server) handleListNotes() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		folderId := vars["folderId"]

		notes, err := s.store.ListNotes(folderId)
		if err != nil {
			respondWithError(w, http.StatusInternalServerError, "Не удалось получить заметки")
			return
		}
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
		var req request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			respondWithError(w, http.StatusBadRequest, "Неверный запрос")
			return
		}

		note, err := s.store.CreateNote(req.Title, req.Content, req.FolderID)
		if err != nil {
			respondWithError(w, http.StatusInternalServerError, "Не удалось создать заметку")
			return
		}
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

		var req request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			respondWithError(w, http.StatusBadRequest, "Неверный запрос")
			return
		}

		note, err := s.store.UpdateNote(noteId, req.Title, req.Content, req.FolderID) // Pass FolderID
		if err != nil {
			respondWithError(w, http.StatusInternalServerError, "Не удалось обновить заметку")
			return
		}
		respondWithJSON(w, http.StatusOK, note)
	}
}

func (s *Server) handleDeleteNote() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		vars := mux.Vars(r)
		noteId := vars["noteId"]

		if err := s.store.DeleteNote(noteId); err != nil {
			respondWithError(w, http.StatusInternalServerError, "Не удалось удалить заметку")
			return
		}
		respondWithJSON(w, http.StatusNoContent, nil)
	}
}

// --- Вспомогательные функции ---

func respondWithError(w http.ResponseWriter, code int, message string) {
	respondWithJSON(w, code, map[string]string{"error": message})
}

func respondWithJSON(w http.ResponseWriter, code int, payload interface{}) {
	response, _ := json.Marshal(payload)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	// Не отправляем тело ответа для статуса 204 No Content
	if payload != nil {
		w.Write(response)
	}
	log.Printf("Ответ: %d", code)
}
