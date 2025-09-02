// Пакет httpapi: REST‑обёртка над сервисами «Доски» (Kanban/Scrum).
//
// Эндпоинты (MVP):
// - /v1/boards (GET, POST)
// - /v1/boards/{boardId}/columns (GET, POST)
// - /v1/columns/{id} (PATCH, DELETE)
// - /v1/boards/{boardId}/columns/order (PUT)
// - /v1/boards/{boardId}/issues (GET, POST)
// - /v1/issues/{issueId} (GET, PATCH, DELETE)
// - /v1/issues/{issueId}:move (POST) — перемещение карточки между колонками
// - /v1/boards/{boardId}/export.csv (GET)
// - /v1/boards/{boardId}/import.csv (POST multipart/form-data, поле file)
// - /v1/cards/{id}/checklist (GET, POST)
// - /v1/checklist_items/{id} (PATCH, DELETE)
// - /v1/cards/{id}/comments (GET, POST)
// - /v1/comments/{id} (DELETE)
// - /v1/cards/{id}/tags:bulk (POST)
// - /v1/cards/{id}/tags/{tag} (DELETE)
package httpapi

import (
    "encoding/csv"
    "encoding/json"
    "net/http"
    "time"
    "github.com/go-chi/chi/v5"
    bsvc "potok/backend/internal/boards/service"
    bmodel "potok/backend/internal/boards/model"
    "strings"
)

type Router struct {
    boards bsvc.BoardService
    issues bsvc.IssueService
}

func NewRouter(boards bsvc.BoardService, issues bsvc.IssueService) http.Handler {
    r := chi.NewRouter()
    api := &Router{boards: boards, issues: issues}
    r.Get("/v1/boards", api.listBoards)        // Список досок
    r.Post("/v1/boards", api.createBoard)
    r.Get("/v1/boards/{boardId}/columns", api.listColumns)
    r.Post("/v1/boards/{boardId}/columns", api.addColumn)
    r.Patch("/v1/columns/{id}", api.patchColumn)
    r.Delete("/v1/columns/{id}", api.deleteColumn)
    r.Put("/v1/boards/{boardId}/columns/order", api.reorderColumns)
    r.Get("/v1/boards/{boardId}/issues", api.listIssues)
    r.Post("/v1/boards/{boardId}/issues", api.createIssue)
    r.Get("/v1/issues/{issueId}", api.getIssue)
    r.Patch("/v1/issues/{issueId}", api.patchIssue)
    r.Delete("/v1/issues/{issueId}", api.deleteIssue)
    // People names (directories)
    r.Get("/v1/boards/{boardId}/people", api.listPeople)
    r.Post("/v1/boards/{boardId}/people", api.addPerson)
    // Custom fields
    r.Get("/v1/boards/{boardId}/fields", api.listFields)
    r.Post("/v1/boards/{boardId}/fields", api.addField)
    r.Get("/v1/cards/{id}/fields", api.listFieldValues)
    r.Put("/v1/cards/{id}/fields", api.putFieldValues)
    // Board notifications
    r.Get("/v1/boards/{boardId}/notifications", api.getNotifications)
    r.Put("/v1/boards/{boardId}/notifications", api.putNotifications)
    // Priorities
    r.Get("/v1/boards/{boardId}/priorities", api.listPriorities)
    r.Post("/v1/boards/{boardId}/priorities", api.upsertPriority)
    r.Delete("/v1/boards/{boardId}/priorities/{key}", api.deletePriority)
    r.Post("/v1/issues/{issueId}:move", api.moveIssue)
    r.Get("/v1/boards/{boardId}/export.csv", api.exportCSV)
    r.Post("/v1/boards/{boardId}/import.csv", api.importCSV)
    // Checklist
    r.Get("/v1/cards/{id}/checklist", api.listChecklist)
    r.Post("/v1/cards/{id}/checklist", api.addChecklist)
    r.Patch("/v1/checklist_items/{id}", api.patchChecklistItem)
    r.Delete("/v1/checklist_items/{id}", api.deleteChecklistItem)
    // Comments
    r.Get("/v1/cards/{id}/comments", api.listComments)
    r.Post("/v1/cards/{id}/comments", api.addComment)
    r.Delete("/v1/comments/{id}", api.deleteComment)
    // Tags
    r.Post("/v1/cards/{id}/tags:bulk", api.tagsBulk)
    r.Delete("/v1/cards/{id}/tags/{tag}", api.deleteTag)
    return r
}

func (rt *Router) listBoards(w http.ResponseWriter, r *http.Request){ items, _ := rt.boards.List(r.Context()); respond(w, http.StatusOK, items) }
func (rt *Router) createBoard(w http.ResponseWriter, r *http.Request){ var req struct{ Name string `json:"name"`; Type string `json:"type"`}; _=json.NewDecoder(r.Body).Decode(&req); b,err:=rt.boards.Create(r.Context(), req.Name, req.Type); if err!=nil{ http.Error(w, err.Error(), 400); return }; respond(w, http.StatusCreated, b) }
func (rt *Router) listColumns(w http.ResponseWriter, r *http.Request){ id:=chi.URLParam(r,"boardId"); items,_ := rt.boards.ListColumns(r.Context(), id); respond(w, http.StatusOK, items) }
func (rt *Router) addColumn(w http.ResponseWriter, r *http.Request){ id:=chi.URLParam(r,"boardId"); var req struct{ Name string `json:"name"`; Wip *int `json:"wipLimit"`}; _=json.NewDecoder(r.Body).Decode(&req); c,err := rt.boards.AddColumn(r.Context(), id, req.Name, req.Wip); if err!=nil{ http.Error(w, err.Error(), 400); return }; respond(w, http.StatusCreated, c) }
func (rt *Router) listIssues(w http.ResponseWriter, r *http.Request){
    id := chi.URLParam(r, "boardId")
    columnID := r.URL.Query().Get("column_id")
    search := r.URL.Query().Get("search")
    tags := r.URL.Query().Get("tags")
    var colPtr *string
    if columnID != "" { colPtr = &columnID }
    var tagsArr []string
    if tags != "" { tagsArr = strings.Split(tags, ",") }
    items, _ := rt.issues.ListByBoard(r.Context(), id, colPtr, search, tagsArr)
    respond(w, http.StatusOK, items)
}
func (rt *Router) createIssue(w http.ResponseWriter, r *http.Request){ id:=chi.URLParam(r,"boardId"); var req bmodel.Issue; _=json.NewDecoder(r.Body).Decode(&req); req.BoardID=id; iss,err:=rt.issues.Create(r.Context(), req); if err!=nil{ http.Error(w, err.Error(), 400); return }; respond(w, http.StatusCreated, iss) }
func (rt *Router) moveIssue(w http.ResponseWriter, r *http.Request){ iid:=chi.URLParam(r,"issueId"); var req struct{ ColumnID string `json:"columnId"`; Position int `json:"position"`}; _=json.NewDecoder(r.Body).Decode(&req); if err:=rt.issues.Move(r.Context(), iid, req.ColumnID, req.Position); err!=nil{ if err == bsvc.ErrWIPLimitExceeded { http.Error(w, err.Error(), 409); return }; http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

func (rt *Router) getIssue(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "issueId"); it, err := rt.issues.Get(r.Context(), id); if err!=nil { http.Error(w, err.Error(), 404); return }; respond(w, http.StatusOK, it) }
func (rt *Router) patchIssue(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "issueId"); var patch map[string]interface{}; _ = json.NewDecoder(r.Body).Decode(&patch); it, err := rt.issues.Update(r.Context(), id, patch); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusOK, it) }
func (rt *Router) deleteIssue(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "issueId"); if err := rt.issues.Delete(r.Context(), id); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

// --- People directory ---
func (rt *Router) listPeople(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); role := r.URL.Query().Get("role"); items, err := rt.boards.ListPeople(r.Context(), board, role); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusOK, items) }
func (rt *Router) addPerson(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); var body struct{ Role string `json:"role"`; Name string `json:"name"` }; _ = json.NewDecoder(r.Body).Decode(&body); if err:=rt.boards.AddPerson(r.Context(), board, body.Role, body.Name); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

// --- Board custom fields ---
func (rt *Router) listFields(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); items, err := rt.boards.ListFields(r.Context(), board); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusOK, items) }
func (rt *Router) addField(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); var body struct{ Name string `json:"name"`; Type string `json:"type"`; Options *string `json:"options"` }; _=json.NewDecoder(r.Body).Decode(&body); it, err := rt.boards.AddField(r.Context(), board, body.Name, body.Type, body.Options); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusCreated, it) }
func (rt *Router) listFieldValues(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); vals, err := rt.boards.ListFieldValues(r.Context(), id); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusOK, vals) }
func (rt *Router) putFieldValues(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); var vals map[string]interface{}; _=json.NewDecoder(r.Body).Decode(&vals); if err := rt.boards.PutFieldValues(r.Context(), id, vals); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

// --- Board notifications cfg ---
func (rt *Router) getNotifications(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); cfg, err := rt.boards.GetNotifications(r.Context(), board); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusOK, cfg) }
func (rt *Router) putNotifications(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); var cfg map[string]interface{}; _=json.NewDecoder(r.Body).Decode(&cfg); if err := rt.boards.PutNotifications(r.Context(), board, cfg); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

// --- Priorities ---
func (rt *Router) listPriorities(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); items, err := rt.boards.ListPriorities(r.Context(), board); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusOK, items) }
func (rt *Router) upsertPriority(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); var body struct{ Key string `json:"key"`; Label string `json:"label"`; ColorHex string `json:"colorHex"`; Position int `json:"position"`}; _=json.NewDecoder(r.Body).Decode(&body); if err:=rt.boards.UpsertPriority(r.Context(), board, body.Key, body.Label, body.ColorHex, body.Position); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }
func (rt *Router) deletePriority(w http.ResponseWriter, r *http.Request){ board := chi.URLParam(r, "boardId"); key := chi.URLParam(r, "key"); if err:=rt.boards.DeletePriority(r.Context(), board, key); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

func (rt *Router) patchColumn(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); var req struct{ Name *string `json:"name"`; Wip *int `json:"wipLimit"`}; _=json.NewDecoder(r.Body).Decode(&req); if err := rt.boards.UpdateColumn(r.Context(), id, req.Name, req.Wip); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }
func (rt *Router) deleteColumn(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); if err := rt.boards.DeleteColumn(r.Context(), id); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }
func (rt *Router) reorderColumns(w http.ResponseWriter, r *http.Request){ var req []struct{ ID string `json:"id"`; Position int `json:"position"`}; _=json.NewDecoder(r.Body).Decode(&req); boardID := chi.URLParam(r, "boardId"); ord := map[string]int{}; for _,it := range req { ord[it.ID] = it.Position }; if err := rt.boards.ReorderColumns(r.Context(), boardID, ord); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

// Checklist
func (rt *Router) listChecklist(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); items, err := rt.issues.ListChecklist(r.Context(), id); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusOK, items) }
func (rt *Router) addChecklist(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); var req struct{ Text string `json:"text"`; Order int `json:"orderIndex"`}; _=json.NewDecoder(r.Body).Decode(&req); item, err := rt.issues.AddChecklistItem(r.Context(), id, req.Text, req.Order); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusCreated, item) }
func (rt *Router) patchChecklistItem(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); var patch map[string]interface{}; _=json.NewDecoder(r.Body).Decode(&patch); if err := rt.issues.UpdateChecklistItem(r.Context(), id, patch); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }
func (rt *Router) deleteChecklistItem(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); if err := rt.issues.DeleteChecklistItem(r.Context(), id); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

// Comments
func (rt *Router) listComments(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); items, err := rt.issues.ListComments(r.Context(), id); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusOK, items) }
func (rt *Router) addComment(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); var req struct{ Body string `json:"body"`}; _=json.NewDecoder(r.Body).Decode(&req); item, err := rt.issues.AddComment(r.Context(), id, req.Body); if err!=nil { http.Error(w, err.Error(), 400); return }; respond(w, http.StatusCreated, item) }
func (rt *Router) deleteComment(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); if err := rt.issues.DeleteComment(r.Context(), id); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

// Tags
func (rt *Router) tagsBulk(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); var req struct{ Tags []string `json:"tags"`}; _=json.NewDecoder(r.Body).Decode(&req); if err := rt.issues.SetTagsBulk(r.Context(), id, req.Tags); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }
func (rt *Router) deleteTag(w http.ResponseWriter, r *http.Request){ id := chi.URLParam(r, "id"); tag := chi.URLParam(r, "tag"); if err := rt.issues.DeleteTag(r.Context(), id, tag); err!=nil { http.Error(w, err.Error(), 400); return }; w.WriteHeader(http.StatusNoContent) }

func (rt *Router) exportCSV(w http.ResponseWriter, r *http.Request){
    // Экспорт задач в простой CSV: summary,description,due_date,priority,labels
    id:=chi.URLParam(r,"boardId"); items,_ := rt.issues.ListByBoard(r.Context(), id, nil, "", nil)
    w.Header().Set("Content-Type","text/csv"); w.Header().Set("Content-Disposition","attachment; filename=issues.csv")
    cw := csv.NewWriter(w); _ = cw.Write([]string{"summary","description","due_date","priority","labels"})
    for _,it := range items { due := ""; if it.DueDate!=nil { due=it.DueDate.UTC().Format(time.RFC3339) }; _ = cw.Write([]string{it.Summary, val(it.Description), due, val(it.Priority), val(it.Labels)}) }
    cw.Flush()
}
func (rt *Router) importCSV(w http.ResponseWriter, r *http.Request){ id:=chi.URLParam(r,"boardId"); r.ParseMultipartForm(10<<20); file,_,err:=r.FormFile("file"); if err!=nil{ http.Error(w, err.Error(), 400); return }; defer file.Close(); cr := csv.NewReader(file); _,_ = cr.Read(); // skip header
    for{ rec,err := cr.Read(); if err!=nil { break }; duePtr := (*time.Time)(nil); if rec[2] != "" { if t,err:=time.Parse(time.RFC3339, rec[2]); err==nil { duePtr=&t } }; _, _ = rt.issues.Create(r.Context(), bmodel.Issue{ ID:"", BoardID:id, ColumnID:"", Type:"task", Summary:rec[0], Description: ptr(rec[1]), Priority: ptr(rec[3]), Labels: ptr(rec[4]), DueDate: duePtr}) }
    w.WriteHeader(http.StatusNoContent)
}

func respond(w http.ResponseWriter, code int, v interface{}){ w.Header().Set("Content-Type","application/json"); w.WriteHeader(code); if v!=nil { _=json.NewEncoder(w).Encode(v) } }
func val(p *string) string { if p==nil { return "" }; return *p }
func ptr(s string) *string { if s=="" { return nil }; return &s }
