// Пакет service: серверная бизнес‑логика «Доски» (Kanban/Scrum) поверх SQLite.
//
// Главные идеи:
// - «Тонкий» клиент: он только отображает и вызывает REST‑методы; все
//   инварианты и операции (позиции, перемещения, ограничения) проверяются и
//   применяются на бэкенде.
// - Позиции карточек в колонках — целые числа, для простоты при перемещении мы
//   выставляем новую позицию как заданную клиентом (MVP). В дальнейшем можно
//   добавить нормализацию/перестройку.
// - Интеграция с календарём: если у задачи указан due_date, автоматически
//   создаётся календарное событие (UTC, час длительности, title = "Due: ...").
// - Взаимосвязь с заметками: у задачи есть поле note_id, куда можно передать id
//   заметки из модуля «Заметки».
package service

import (
    "context"
    "database/sql"
    "errors"
    "strings"
    "time"
    "github.com/google/uuid"
    bmodel "potok/backend/internal/boards/model"
)

type BoardService interface {
    // List — вернуть все доски.
    List(ctx context.Context) ([]bmodel.Board, error)
    // Create — создать доску (kanban|scrum).
    Create(ctx context.Context, name, btype string) (bmodel.Board, error)
    // AddColumn — добавить колонку на доску, опционально ограничив WIP.
    AddColumn(ctx context.Context, boardID, name string, wip *int) (bmodel.Column, error)
    // ListColumns — вернуть колонки доски в порядке position.
    ListColumns(ctx context.Context, boardID string) ([]bmodel.Column, error)
    // UpdateColumn — изменить имя/WIP колонки.
    UpdateColumn(ctx context.Context, columnID string, name *string, wip *int) error
    // DeleteColumn — удалить колонку (каскадно удалит задачи по FK).
    DeleteColumn(ctx context.Context, columnID string) error
    // DeleteBoard — удалить доску со всеми колонками и задачами.
    DeleteBoard(ctx context.Context, boardID string) error
    // ReorderColumns — массовое обновление позиций.
    ReorderColumns(ctx context.Context, boardID string, orders map[string]int) error
    // People directory per board
    ListPeople(ctx context.Context, boardID, role string) ([]string, error)
    AddPerson(ctx context.Context, boardID, role, name string) error
    // Custom fields per board and values per issue
    ListFields(ctx context.Context, boardID string) ([]map[string]interface{}, error)
    AddField(ctx context.Context, boardID, name, ftype string, optionsJSON *string) (map[string]interface{}, error)
    ListFieldValues(ctx context.Context, issueID string) (map[string]interface{}, error)
    PutFieldValues(ctx context.Context, issueID string, values map[string]interface{}) error
    // Notifications config
    GetNotifications(ctx context.Context, boardID string) (map[string]interface{}, error)
    PutNotifications(ctx context.Context, boardID string, cfg map[string]interface{}) error
    // Priorities
    ListPriorities(ctx context.Context, boardID string) ([]map[string]interface{}, error)
    UpsertPriority(ctx context.Context, boardID, key, label, color string, position int) error
    DeletePriority(ctx context.Context, boardID, key string) error
}

type IssueService interface {
    // Create — создать задачу. Если DueDate задан — создаётся событие в календаре.
    Create(ctx context.Context, iss bmodel.Issue) (bmodel.Issue, error)
    // ListByBoard — вернуть задачи доски, с фильтрами.
    ListByBoard(ctx context.Context, boardID string, columnID *string, search string, tags []string) ([]bmodel.Issue, error)
    // Move — переместить задачу в другую колонку/позицию.
    Move(ctx context.Context, issueID, toColumnID string, newPosition int) error
    // Get — получить задачу по id.
    Get(ctx context.Context, issueID string) (bmodel.Issue, error)
    // Update — частичное обновление полей задачи.
    Update(ctx context.Context, issueID string, patch map[string]interface{}) (bmodel.Issue, error)
    // Delete — удалить задачу.
    Delete(ctx context.Context, issueID string) error
    // ArchiveDoneIssues — архивировать (удалить) задачи из колонок "Done".
    ArchiveDoneIssues(ctx context.Context, boardID string) error
    // ListArchivedIssues — вернуть все задачи из архива.
    ListArchivedIssues(ctx context.Context) ([]bmodel.Issue, error)
    // DeleteArchivedIssue — окончательно удалить задачу из архива.
    DeleteArchivedIssue(ctx context.Context, issueID string) error
    // GetArchivedIssue — получить одну задачу из архива по ID.
    GetArchivedIssue(ctx context.Context, issueID string) (bmodel.Issue, error)
    // Checklist
    ListChecklist(ctx context.Context, issueID string) ([]map[string]interface{}, error)
    AddChecklistItem(ctx context.Context, issueID, text string, order int) (map[string]interface{}, error)
    UpdateChecklistItem(ctx context.Context, itemID string, patch map[string]interface{}) error
    DeleteChecklistItem(ctx context.Context, itemID string) error
    // Comments
    ListComments(ctx context.Context, issueID string) ([]map[string]interface{}, error)
    AddComment(ctx context.Context, issueID, body string) (map[string]interface{}, error)
    DeleteComment(ctx context.Context, commentID string) error
    // Tags
    SetTagsBulk(ctx context.Context, issueID string, tags []string) error
    DeleteTag(ctx context.Context, issueID, tag string) error
}

type sqliteBoardService struct { db *sql.DB }
type sqliteIssueService struct { db *sql.DB }

func NewSQLiteBoardService(db *sql.DB) BoardService { return &sqliteBoardService{db: db} }
func NewSQLiteIssueService(db *sql.DB) IssueService { return &sqliteIssueService{db: db} }

func (s *sqliteBoardService) List(ctx context.Context) ([]bmodel.Board, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT id,name,type,created_at,updated_at FROM boards ORDER BY created_at`)
    if err!=nil { return nil, err }
    defer rows.Close()
    out := []bmodel.Board{}
    for rows.Next(){ var b bmodel.Board; var c,u string; if err:=rows.Scan(&b.ID,&b.Name,&b.Type,&c,&u); err!=nil { return nil, err }; b.CreatedAt,_=time.Parse(time.RFC3339,c); b.UpdatedAt,_=time.Parse(time.RFC3339,u); out=append(out,b) }
    return out, nil
}
func (s *sqliteBoardService) Create(ctx context.Context, name, btype string) (bmodel.Board, error) {
    if name == "" {
        return bmodel.Board{}, errors.New("empty name")
    }
    if btype == "" {
        btype = "kanban"
    }
    b := bmodel.Board{ID: uuid.New().String(), Name: name, Type: btype, CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()}
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return bmodel.Board{}, err
    }
    // В случае ошибки откатываем транзакцию
    defer tx.Rollback()

    // Создаём доску
    if _, err := tx.ExecContext(ctx, `INSERT INTO boards(id,name,type,created_at,updated_at) VALUES (?,?,?,?,?)`, b.ID, b.Name, b.Type, b.CreatedAt.Format(time.RFC3339), b.UpdatedAt.Format(time.RFC3339)); err != nil {
        return bmodel.Board{}, err
    }

    // Создаём колонки по умолчанию
    now := time.Now().UTC().Format(time.RFC3339)
    defaultColumns := []struct {
        name string
        pos  int
    }{{"To Do", 1}, {"In Progress", 2}, {"Done", 3}}
    for _, d := range defaultColumns {
        if _, err := tx.ExecContext(ctx, `INSERT INTO board_columns(id,board_id,name,wip_limit,position,created_at,updated_at) VALUES (?,?,?,?,?,?,?)`, uuid.New().String(), b.ID, d.name, nil, d.pos, now, now); err != nil {
            return bmodel.Board{}, err
        }
    }

    // Создаём приоритеты по умолчанию
    defaultPriorities := []struct {
        key      string
        label    string
        color    string
        position int
    }{
        {"HIGHEST", "Highest", "#F44336", 1},
        {"HIGH", "High", "#FF9800", 2},
        {"MEDIUM", "Medium", "#2196F3", 3},
        {"LOW", "Low", "#4CAF50", 4},
    }
    for _, p := range defaultPriorities {
        if _, err := tx.ExecContext(ctx, `INSERT INTO board_priorities(board_id,pkey,label,color_hex,position) VALUES (?,?,?,?,?)`, b.ID, p.key, p.label, p.color, p.position); err != nil {
            return bmodel.Board{}, err
        }
    }

    // Завершаем транзакцию
    if err := tx.Commit(); err != nil {
        return bmodel.Board{}, err
    }
    return b, nil
}
func (s *sqliteBoardService) AddColumn(ctx context.Context, boardID, name string, wip *int) (bmodel.Column, error) {
    // position = max(position)+1
    var pos int; _ = s.db.QueryRowContext(ctx, `SELECT COALESCE(MAX(position),0)+1 FROM board_columns WHERE board_id=?`, boardID).Scan(&pos)
    c := bmodel.Column{ ID: uuid.New().String(), BoardID: boardID, Name: name, Position: pos, CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC() }
    if wip!=nil { c.WIPLimit = wip }
    _, err := s.db.ExecContext(ctx, `INSERT INTO board_columns(id,board_id,name,wip_limit,position,created_at,updated_at) VALUES (?,?,?,?,?,?,?)`, c.ID,c.BoardID,c.Name,c.WIPLimit, c.Position, c.CreatedAt.Format(time.RFC3339), c.UpdatedAt.Format(time.RFC3339))
    if err!=nil { return bmodel.Column{}, err }
    return c, nil
}
func (s *sqliteBoardService) ListColumns(ctx context.Context, boardID string) ([]bmodel.Column, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT id,board_id,name,wip_limit,position,created_at,updated_at FROM board_columns WHERE board_id=? ORDER BY position`, boardID)
    if err!=nil { return nil, err }
    defer rows.Close()
    out := []bmodel.Column{}
    for rows.Next(){ var c bmodel.Column; var wip sql.NullInt64; var ca,ua string; if err:=rows.Scan(&c.ID,&c.BoardID,&c.Name,&wip,&c.Position,&ca,&ua); err!=nil { return nil, err }; if wip.Valid { v:=int(wip.Int64); c.WIPLimit=&v }; c.CreatedAt,_=time.Parse(time.RFC3339,ca); c.UpdatedAt,_=time.Parse(time.RFC3339,ua); out=append(out,c) }
    return out, nil
}

func (s *sqliteBoardService) UpdateColumn(ctx context.Context, columnID string, name *string, wip *int) error {
    // Partial update
    if name == nil && wip == nil { return nil }
    if name != nil {
        if _, err := s.db.ExecContext(ctx, `UPDATE board_columns SET name=?, updated_at=? WHERE id=?`, *name, time.Now().UTC().Format(time.RFC3339), columnID); err != nil { return err }
    }
    if wip != nil {
        if _, err := s.db.ExecContext(ctx, `UPDATE board_columns SET wip_limit=?, updated_at=? WHERE id=?`, *wip, time.Now().UTC().Format(time.RFC3339), columnID); err != nil { return err }
    }
    return nil
}

func (s *sqliteBoardService) DeleteColumn(ctx context.Context, columnID string) error {
    _, err := s.db.ExecContext(ctx, `DELETE FROM board_columns WHERE id=?`, columnID)
    return err
}

func (s *sqliteBoardService) DeleteBoard(ctx context.Context, boardID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() // Rollback on error in case of panic

	// Сначала найдём все ID задач (issues), чтобы удалить связанные с ними данные.
	var issueIDs []string
	rows, err := tx.QueryContext(ctx, `SELECT id FROM issues WHERE board_id=?`, boardID)
	if err != nil {
		return err
	}
	// Важно итерироваться по всем результатам и закрыть rows перед следующими запросами в транзакции.
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		issueIDs = append(issueIDs, id)
	}
	rows.Close() // Закрываем rows досрочно.

	if len(issueIDs) > 0 {
		// Генерируем плейсхолдеры для IN (...)
		qMarks := strings.Repeat("?,", len(issueIDs)-1) + "?"
		args := make([]interface{}, len(issueIDs))
		for i, id := range issueIDs {
			args[i] = id
		}

		// Удаляем все данные, связанные с задачами
		if _, err := tx.ExecContext(ctx, `DELETE FROM issue_tags WHERE issue_id IN (`+qMarks+`)`, args...); err != nil { return err }
		if _, err := tx.ExecContext(ctx, `DELETE FROM issue_comments WHERE issue_id IN (`+qMarks+`)`, args...); err != nil { return err }
		if _, err := tx.ExecContext(ctx, `DELETE FROM issue_checklist_items WHERE issue_id IN (`+qMarks+`)`, args...); err != nil { return err }
		if _, err := tx.ExecContext(ctx, `DELETE FROM issue_field_values WHERE issue_id IN (`+qMarks+`)`, args...); err != nil { return err }
		if _, err := tx.ExecContext(ctx, `DELETE FROM activity_log WHERE entity_type='CARD' AND entity_id IN (`+qMarks+`)`, args...); err != nil { return err }
	}

	// Удаляем данные, напрямую связанные с доской
	if _, err := tx.ExecContext(ctx, `DELETE FROM issues WHERE board_id=?`, boardID); err != nil { return err }
	if _, err := tx.ExecContext(ctx, `DELETE FROM board_columns WHERE board_id=?`, boardID); err != nil { return err }
	if _, err := tx.ExecContext(ctx, `DELETE FROM board_people WHERE board_id=?`, boardID); err != nil { return err }
	if _, err := tx.ExecContext(ctx, `DELETE FROM board_fields WHERE board_id=?`, boardID); err != nil { return err }
	if _, err := tx.ExecContext(ctx, `DELETE FROM board_notifications WHERE board_id=?`, boardID); err != nil { return err }
	if _, err := tx.ExecContext(ctx, `DELETE FROM board_priorities WHERE board_id=?`, boardID); err != nil { return err }

	// Наконец, удаляем саму доску
	if _, err := tx.ExecContext(ctx, `DELETE FROM boards WHERE id=?`, boardID); err != nil { return err }

	return tx.Commit()
}

func (s *sqliteBoardService) ReorderColumns(ctx context.Context, boardID string, orders map[string]int) error {
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil { return err }
    now := time.Now().UTC().Format(time.RFC3339)
    for id, pos := range orders {
        if _, err := tx.ExecContext(ctx, `UPDATE board_columns SET position=?, updated_at=? WHERE id=? AND board_id=?`, pos, now, id, boardID); err != nil { tx.Rollback(); return err }
    }
    return tx.Commit()
}

// People directory
func (s *sqliteBoardService) ListPeople(ctx context.Context, boardID, role string) ([]string, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT name FROM board_people WHERE board_id=? AND (?='' OR role=?) ORDER BY name`, boardID, role, role)
    if err!=nil { return nil, err }
    defer rows.Close()
    out := []string{}
    for rows.Next(){ var n string; if err:=rows.Scan(&n); err!=nil { return nil, err }; out = append(out, n) }
    return out, nil
}
func (s *sqliteBoardService) AddPerson(ctx context.Context, boardID, role, name string) error {
    if strings.TrimSpace(name)=="" { return nil }
    _, err := s.db.ExecContext(ctx, `INSERT OR IGNORE INTO board_people(board_id,role,name) VALUES (?,?,?)`, boardID, role, name)
    return err
}

// Custom fields
func (s *sqliteBoardService) ListFields(ctx context.Context, boardID string) ([]map[string]interface{}, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT id,name,ftype,options_json FROM board_fields WHERE board_id=? ORDER BY created_at`, boardID)
    if err!=nil { return nil, err }
    defer rows.Close()
    out := make([]map[string]interface{}, 0)
    for rows.Next(){ var id, name, ftype string; var opt sql.NullString; if err:=rows.Scan(&id,&name,&ftype,&opt); err!=nil { return nil, err }; out = append(out, map[string]interface{}{"id":id,"name":name,"type":ftype, "options": func() interface{} { if opt.Valid { return opt.String }; return nil }()}) }
    return out, nil
}
func (s *sqliteBoardService) AddField(ctx context.Context, boardID, name, ftype string, optionsJSON *string) (map[string]interface{}, error) {
    id := uuid.New().String(); now := time.Now().UTC().Format(time.RFC3339)
    _, err := s.db.ExecContext(ctx, `INSERT INTO board_fields(id,board_id,name,ftype,options_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?)`, id, boardID, name, ftype, optionsJSON, now, now)
    if err!=nil { return nil, err }
    return map[string]interface{}{"id":id,"name":name,"type":ftype,"options":optionsJSON}, nil
}
func (s *sqliteBoardService) ListFieldValues(ctx context.Context, issueID string) (map[string]interface{}, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT f.name, v.value_json FROM issue_field_values v JOIN board_fields f ON f.id=v.field_id WHERE v.issue_id=?`, issueID)
    if err!=nil { return nil, err }
    defer rows.Close()
    out := map[string]interface{}{}
    for rows.Next(){ var name string; var val sql.NullString; if err:=rows.Scan(&name,&val); err!=nil { return nil, err }; if val.Valid { out[name] = val.String } }
    return out, nil
}
func (s *sqliteBoardService) PutFieldValues(ctx context.Context, issueID string, values map[string]interface{}) error {
    tx, err := s.db.BeginTx(ctx, nil); if err!=nil { return err }
    for k,v := range values {
        // resolve field id by name within the board of this issue
        var fieldID string
        err := tx.QueryRowContext(ctx, `SELECT bf.id FROM board_fields bf JOIN issues i ON i.board_id=bf.board_id WHERE i.id=? AND bf.name=?`, issueID, k).Scan(&fieldID)
        if err!=nil { tx.Rollback(); return err }
        _, err = tx.ExecContext(ctx, `INSERT OR REPLACE INTO issue_field_values(issue_id,field_id,value_json) VALUES (?,?,?)`, issueID, fieldID, v)
        if err!=nil { tx.Rollback(); return err }
    }
    return tx.Commit()
}

// Notifications cfg
func (s *sqliteBoardService) GetNotifications(ctx context.Context, boardID string) (map[string]interface{}, error) {
    row := s.db.QueryRowContext(ctx, `SELECT due_soon_hours, create_calendar_event, create_default_reminders, reminder_offsets_csv FROM board_notifications WHERE board_id=?`, boardID)
    var due int; var cce, cdr int; var offs sql.NullString
    if err := row.Scan(&due,&cce,&cdr,&offs); err != nil {
        if err==sql.ErrNoRows { return map[string]interface{}{"dueSoonHours":24,"createCalendarEvent":1,"createDefaultReminders":0,"reminderOffsetsCsv":nil}, nil }
        return nil, err
    }
    return map[string]interface{}{"dueSoonHours":due,"createCalendarEvent":cce,"createDefaultReminders":cdr,"reminderOffsetsCsv": func() interface{} { if offs.Valid { return offs.String }; return nil }()}, nil
}
func (s *sqliteBoardService) PutNotifications(ctx context.Context, boardID string, cfg map[string]interface{}) error {
    // upsert
    _, err := s.db.ExecContext(ctx, `INSERT INTO board_notifications(board_id,due_soon_hours,create_calendar_event,create_default_reminders,reminder_offsets_csv) VALUES (?,?,?,?,?)
        ON CONFLICT(board_id) DO UPDATE SET due_soon_hours=excluded.due_soon_hours, create_calendar_event=excluded.create_calendar_event, create_default_reminders=excluded.create_default_reminders, reminder_offsets_csv=excluded.reminder_offsets_csv`,
        boardID, cfg["dueSoonHours"], cfg["createCalendarEvent"], cfg["createDefaultReminders"], cfg["reminderOffsetsCsv"],
    )
    return err
}

// Priorities
func (s *sqliteBoardService) ListPriorities(ctx context.Context, boardID string) ([]map[string]interface{}, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT pkey,label,color_hex,position FROM board_priorities WHERE board_id=? ORDER BY position`, boardID)
    if err!=nil { return nil, err }
    defer rows.Close()
    out := make([]map[string]interface{}, 0)
    for rows.Next(){ var k,l,c string; var pos int; if err:=rows.Scan(&k,&l,&c,&pos); err!=nil { return nil, err }; out = append(out, map[string]interface{}{"key":k,"label":l,"colorHex":c,"position":pos}) }
    return out, nil
}
func (s *sqliteBoardService) UpsertPriority(ctx context.Context, boardID, key, label, color string, position int) error {
    _, err := s.db.ExecContext(ctx, `INSERT INTO board_priorities(board_id,pkey,label,color_hex,position) VALUES (?,?,?,?,?)
        ON CONFLICT(board_id,pkey) DO UPDATE SET label=excluded.label, color_hex=excluded.color_hex, position=excluded.position`, boardID, key, label, color, position)
    return err
}
func (s *sqliteBoardService) DeletePriority(ctx context.Context, boardID, key string) error {
    _, err := s.db.ExecContext(ctx, `DELETE FROM board_priorities WHERE board_id=? AND pkey=?`, boardID, key)
    return err
}

var ErrWIPLimitExceeded = errors.New("wip limit exceeded")

func (s *sqliteIssueService) Create(ctx context.Context, iss bmodel.Issue) (bmodel.Issue, error) {
    if iss.ID=="" { iss.ID = uuid.New().String() }
    // position = max(position)+1 в колонке
    var pos int; _ = s.db.QueryRowContext(ctx, `SELECT COALESCE(MAX(position),0)+1 FROM issues WHERE board_id=? AND column_id=?`, iss.BoardID, iss.ColumnID).Scan(&pos)
    iss.Position = pos
    // WIP check
    var wip sql.NullInt64
    _ = s.db.QueryRowContext(ctx, `SELECT wip_limit FROM board_columns WHERE id=?`, iss.ColumnID).Scan(&wip)
    if wip.Valid {
        var cnt int
        _ = s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM issues WHERE column_id=?`, iss.ColumnID).Scan(&cnt)
        if cnt >= int(wip.Int64) { return bmodel.Issue{}, ErrWIPLimitExceeded }
    }
    now := time.Now().UTC(); iss.CreatedAt, iss.UpdatedAt = now, now
    var due *string
    if iss.DueDate != nil { s := iss.DueDate.UTC().Format(time.RFC3339); due=&s }
    _, err := s.db.ExecContext(ctx, `INSERT INTO issues(id,board_id,column_id,type,summary,description,priority,labels,due_date,created_by_name,assigned_to_name,responsible_name,note_id,position,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, iss.ID,iss.BoardID,iss.ColumnID,iss.Type,iss.Summary,iss.Description,iss.Priority,iss.Labels,due,iss.CreatedBy,iss.AssignedTo,iss.Responsible,iss.NoteID,iss.Position, iss.CreatedAt.Format(time.RFC3339), iss.UpdatedAt.Format(time.RFC3339))
    if err!=nil { return bmodel.Issue{}, err }
    // Activity log
    _, _ = s.db.ExecContext(ctx, `INSERT INTO activity_log(id,ts,entity_type,entity_id,action,after_json) VALUES (?,?,?,?,?,?)`, uuid.New().String(), now.Format(time.RFC3339), "CARD", iss.ID, "CREATED", "")
    // Автосоздание события в календаре по due_date
    if iss.DueDate != nil {
        title := "Due: "+iss.Summary
        _, _ = s.db.ExecContext(ctx, `INSERT INTO events(uid,calendar_uid,title,start_utc,end_utc,is_all_day,tzid,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)`, uuid.New().String(), "cal-boards", title, iss.DueDate.UTC().Format(time.RFC3339), iss.DueDate.UTC().Add(time.Hour).Format(time.RFC3339), 0, "UTC", now.Format(time.RFC3339), now.Format(time.RFC3339))
    }
    return iss, nil
}

func (s *sqliteIssueService) ListByBoard(ctx context.Context, boardID string, columnID *string, search string, tags []string) ([]bmodel.Issue, error) {
    // Build WHERE
    where := []string{"board_id = ?"}
    args := []interface{}{boardID}
    if columnID != nil && *columnID != "" { where = append(where, "column_id = ?"); args = append(args, *columnID) }
    if search != "" {
        like := "%"+strings.ToLower(search)+"%"
        where = append(where, "(lower(summary) LIKE ? OR lower(COALESCE(description,'')) LIKE ?)")
        args = append(args, like, like)
    }
    if len(tags) > 0 {
        // filter by existence of any of the tags
        placeholders := strings.Repeat("?,", len(tags))
        placeholders = placeholders[:len(placeholders)-1]
        where = append(where, "id IN (SELECT issue_id FROM issue_tags WHERE tag IN ("+placeholders+"))")
        for _, t := range tags { args = append(args, t) }
    }
    query := `SELECT id,board_id,column_id,type,summary,description,priority,labels,due_date,created_by_name,assigned_to_name,responsible_name,note_id,position,created_at,updated_at FROM issues WHERE ` + strings.Join(where, " AND ") + ` ORDER BY column_id, position`
    rows, err := s.db.QueryContext(ctx, query, args...)
    if err!=nil { return nil, err }
    defer rows.Close()
    out := []bmodel.Issue{}
    for rows.Next(){ var i bmodel.Issue; var desc,prio,labels,due,cb,as,res,note sql.NullString; var ca,ua string; if err:=rows.Scan(&i.ID,&i.BoardID,&i.ColumnID,&i.Type,&i.Summary,&desc,&prio,&labels,&due,&cb,&as,&res,&note,&i.Position,&ca,&ua); err!=nil { return nil, err }; if desc.Valid { i.Description=&desc.String }; if prio.Valid { i.Priority=&prio.String }; if labels.Valid { i.Labels=&labels.String }; if due.Valid { t,_:=time.Parse(time.RFC3339,due.String); i.DueDate=&t }; if cb.Valid { i.CreatedBy=&cb.String }; if as.Valid { i.AssignedTo=&as.String }; if res.Valid { i.Responsible=&res.String }; if note.Valid { i.NoteID=&note.String }; i.CreatedAt,_=time.Parse(time.RFC3339,ca); i.UpdatedAt,_=time.Parse(time.RFC3339,ua); out=append(out,i) }
    return out, nil
}

func (s *sqliteIssueService) Move(ctx context.Context, issueID, toColumnID string, newPosition int) error {
    // WIP check
    var wip sql.NullInt64
    _ = s.db.QueryRowContext(ctx, `SELECT wip_limit FROM board_columns WHERE id=?`, toColumnID).Scan(&wip)
    if wip.Valid {
        var cnt int
        _ = s.db.QueryRowContext(ctx, `SELECT COUNT(1) FROM issues WHERE column_id=?`, toColumnID).Scan(&cnt)
        if cnt >= int(wip.Int64) { return ErrWIPLimitExceeded }
    }
    _, err := s.db.ExecContext(ctx, `UPDATE issues SET column_id=?, position=?, updated_at=? WHERE id=?`, toColumnID, newPosition, time.Now().UTC().Format(time.RFC3339), issueID)
    if err == nil {
        _, _ = s.db.ExecContext(ctx, `INSERT INTO activity_log(id,ts,entity_type,entity_id,action) VALUES (?,?,?,?,?)`, uuid.New().String(), time.Now().UTC().Format(time.RFC3339), "CARD", issueID, "MOVED")
    }
    return err
}

func (s *sqliteIssueService) Get(ctx context.Context, issueID string) (bmodel.Issue, error) {
    row := s.db.QueryRowContext(ctx, `SELECT id,board_id,column_id,type,summary,description,priority,labels,due_date,created_by_name,assigned_to_name,responsible_name,note_id,position,created_at,updated_at FROM issues WHERE id=?`, issueID)
    var i bmodel.Issue; var desc,prio,labels,due,cb,as,res,note sql.NullString; var ca,ua string
    if err := row.Scan(&i.ID,&i.BoardID,&i.ColumnID,&i.Type,&i.Summary,&desc,&prio,&labels,&due,&cb,&as,&res,&note,&i.Position,&ca,&ua); err != nil { return bmodel.Issue{}, err }
    if desc.Valid { i.Description=&desc.String }; if prio.Valid { i.Priority=&prio.String }; if labels.Valid { i.Labels=&labels.String }; if due.Valid { t,_:=time.Parse(time.RFC3339,due.String); i.DueDate=&t }; if cb.Valid { i.CreatedBy=&cb.String }; if as.Valid { i.AssignedTo=&as.String }; if res.Valid { i.Responsible=&res.String }; if note.Valid { i.NoteID=&note.String }
    i.CreatedAt,_=time.Parse(time.RFC3339,ca); i.UpdatedAt,_=time.Parse(time.RFC3339,ua)
    return i, nil
}

func (s *sqliteIssueService) Update(ctx context.Context, issueID string, patch map[string]interface{}) (bmodel.Issue, error) {
    // Simple field updates: summary, description, priority, labels, due_date, note_id
    sets := []string{}
    args := []interface{}{}
    if v,ok := patch["type"]; ok { sets = append(sets, "type=?"); args = append(args, v) }
    if v,ok := patch["summary"]; ok { sets = append(sets, "summary=?"); args = append(args, v) }
    if v,ok := patch["description"]; ok { sets = append(sets, "description=?"); args = append(args, v) }
    if v,ok := patch["priority"]; ok { sets = append(sets, "priority=?"); args = append(args, v) }
    if v,ok := patch["labels"]; ok { sets = append(sets, "labels=?"); args = append(args, v) }
    if v,ok := patch["due_date"]; ok { sets = append(sets, "due_date=?"); args = append(args, v) }
    if v,ok := patch["createdBy"]; ok { sets = append(sets, "created_by_name=?"); args = append(args, v) }
    if v,ok := patch["assignedTo"]; ok { sets = append(sets, "assigned_to_name=?"); args = append(args, v) }
    if v,ok := patch["responsible"]; ok { sets = append(sets, "responsible_name=?"); args = append(args, v) }
    if v,ok := patch["note_id"]; ok { sets = append(sets, "note_id=?"); args = append(args, v) }
    if len(sets) == 0 { return s.Get(ctx, issueID) }
    sets = append(sets, "updated_at=?")
    args = append(args, time.Now().UTC().Format(time.RFC3339), issueID)
    _, err := s.db.ExecContext(ctx, `UPDATE issues SET `+strings.Join(sets, ", ")+` WHERE id=?`, args...)
    if err != nil { return bmodel.Issue{}, err }
    _, _ = s.db.ExecContext(ctx, `INSERT INTO activity_log(id,ts,entity_type,entity_id,action) VALUES (?,?,?,?,?)`, uuid.New().String(), time.Now().UTC().Format(time.RFC3339), "CARD", issueID, "UPDATED")
    return s.Get(ctx, issueID)
}

func (s *sqliteIssueService) Delete(ctx context.Context, issueID string) error {
    _, err := s.db.ExecContext(ctx, `DELETE FROM issues WHERE id=?`, issueID)
    if err == nil {
        _, _ = s.db.ExecContext(ctx, `INSERT INTO activity_log(id,ts,entity_type,entity_id,action) VALUES (?,?,?,?,?)`, uuid.New().String(), time.Now().UTC().Format(time.RFC3339), "CARD", issueID, "DELETED")
    }
    return err
}

func (s *sqliteIssueService) ArchiveDoneIssues(ctx context.Context, boardID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

    // Шаг 0: Убедиться, что таблица архива существует.
    _, err = tx.ExecContext(ctx, `
        CREATE TABLE IF NOT EXISTS archived_issues (
            id TEXT PRIMARY KEY,
            board_id TEXT,
            column_id TEXT,
            type TEXT,
            summary TEXT,
            description TEXT,
            priority TEXT,
            labels TEXT,
            due_date TEXT,
            created_by_name TEXT,
            assigned_to_name TEXT,
            responsible_name TEXT,
            note_id TEXT,
            position INTEGER,
            created_at TEXT,
            updated_at TEXT,
            archived_at TEXT NOT NULL
        )`)
    if err != nil {
        return err
    }

	// 1. Найти ID колонок с названием "Done"
	rows, err := tx.QueryContext(ctx, `SELECT id FROM board_columns WHERE board_id=? AND name=?`, boardID, "Done")
	if err != nil { return err }

	var doneColumnIDs []interface{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil { rows.Close(); return err }
		doneColumnIDs = append(doneColumnIDs, id)
	}
	rows.Close()
	if err = rows.Err(); err != nil { return err }
	if len(doneColumnIDs) == 0 { return nil } // Нечего архивировать

	qMarks := strings.Repeat("?,", len(doneColumnIDs)-1) + "?"

	// 2. Копировать задачи в `archived_issues`
	// ПРИМЕЧАНИЕ: Эта таблица должна быть создана вручную.
	// Ее структура должна совпадать с `issues` + поле `archived_at`
	_, err = tx.ExecContext(ctx, `
		INSERT INTO archived_issues (id, board_id, column_id, type, summary, description, priority, labels, due_date, created_by_name, assigned_to_name, responsible_name, note_id, position, created_at, updated_at, archived_at)
		SELECT id, board_id, column_id, type, summary, description, priority, labels, due_date, created_by_name, assigned_to_name, responsible_name, note_id, position, created_at, updated_at, ?
		FROM issues
		WHERE column_id IN (`+qMarks+`)`, append([]interface{}{time.Now().UTC().Format(time.RFC3339)}, doneColumnIDs...)...)
	if err != nil { return err }

	// 3. Удалить исходные задачи
	// 3. Удалить исходные задачи
	_, err = tx.ExecContext(ctx, `DELETE FROM issues WHERE column_id IN (`+qMarks+`)`, doneColumnIDs...)
	if err != nil { return err }

	return tx.Commit()
}

func (s *sqliteIssueService) ListArchivedIssues(ctx context.Context) ([]bmodel.Issue, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT id,board_id,column_id,type,summary,description,priority,labels,due_date,created_by_name,assigned_to_name,responsible_name,note_id,position,created_at,updated_at FROM archived_issues ORDER BY archived_at DESC`)
    if err!=nil { return nil, err }
    defer rows.Close()
    out := []bmodel.Issue{}
    for rows.Next(){
        var i bmodel.Issue
        var desc,prio,labels,due,cb,as,res,note sql.NullString
        var ca,ua string
        if err:=rows.Scan(&i.ID,&i.BoardID,&i.ColumnID,&i.Type,&i.Summary,&desc,&prio,&labels,&due,&cb,&as,&res,&note,&i.Position,&ca,&ua); err!=nil { return nil, err }
        if desc.Valid { i.Description=&desc.String }
        if prio.Valid { i.Priority=&prio.String }
        if labels.Valid { i.Labels=&labels.String }
        if due.Valid { t,_:=time.Parse(time.RFC3339,due.String); i.DueDate=&t }
        if cb.Valid { i.CreatedBy=&cb.String }
        if as.Valid { i.AssignedTo=&as.String }
        if res.Valid { i.Responsible=&res.String }
        if note.Valid { i.NoteID=&note.String }
        i.CreatedAt,_=time.Parse(time.RFC3339,ca)
        i.UpdatedAt,_=time.Parse(time.RFC3339,ua)
        out=append(out,i)
    }
    return out, nil
}

func (s *sqliteIssueService) DeleteArchivedIssue(ctx context.Context, issueID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM archived_issues WHERE id=?`, issueID)
	return err
}

func (s *sqliteIssueService) GetArchivedIssue(ctx context.Context, issueID string) (bmodel.Issue, error) {
    row := s.db.QueryRowContext(ctx, `SELECT id,board_id,column_id,type,summary,description,priority,labels,due_date,created_by_name,assigned_to_name,responsible_name,note_id,position,created_at,updated_at FROM archived_issues WHERE id=?`, issueID)
    var i bmodel.Issue; var desc,prio,labels,due,cb,as,res,note sql.NullString; var ca,ua string
    if err := row.Scan(&i.ID,&i.BoardID,&i.ColumnID,&i.Type,&i.Summary,&desc,&prio,&labels,&due,&cb,&as,&res,&note,&i.Position,&ca,&ua); err != nil { return bmodel.Issue{}, err }
    if desc.Valid { i.Description=&desc.String }; if prio.Valid { i.Priority=&prio.String }; if labels.Valid { i.Labels=&labels.String }; if due.Valid { t,_:=time.Parse(time.RFC3339,due.String); i.DueDate=&t }; if cb.Valid { i.CreatedBy=&cb.String }; if as.Valid { i.AssignedTo=&as.String }; if res.Valid { i.Responsible=&res.String }; if note.Valid { i.NoteID=&note.String }
    i.CreatedAt,_=time.Parse(time.RFC3339,ca); i.UpdatedAt,_=time.Parse(time.RFC3339,ua)
    return i, nil
}

// Checklist
func (s *sqliteIssueService) ListChecklist(ctx context.Context, issueID string) ([]map[string]interface{}, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT id,text,is_done,order_index FROM issue_checklist_items WHERE issue_id=? ORDER BY order_index`, issueID)
    if err != nil { return nil, err }
    defer rows.Close()
    var out []map[string]interface{}
    for rows.Next(){ var id, text string; var done int; var idx int; if err:=rows.Scan(&id,&text,&done,&idx); err!=nil{ return nil, err }; out = append(out, map[string]interface{}{"id":id,"text":text,"isDone":done==1,"orderIndex":idx}) }
    return out, nil
}
func (s *sqliteIssueService) AddChecklistItem(ctx context.Context, issueID, text string, order int) (map[string]interface{}, error) {
    id := uuid.New().String()
    if _, err := s.db.ExecContext(ctx, `INSERT INTO issue_checklist_items(id,issue_id,text,is_done,order_index) VALUES (?,?,?,?,?)`, id, issueID, text, 0, order); err != nil { return nil, err }
    return map[string]interface{}{"id":id,"text":text,"isDone":false,"orderIndex":order}, nil
}
func (s *sqliteIssueService) UpdateChecklistItem(ctx context.Context, itemID string, patch map[string]interface{}) error {
    sets := []string{}
    args := []interface{}{}
    if v,ok := patch["text"]; ok { sets = append(sets, "text=?"); args = append(args, v) }
    if v,ok := patch["isDone"]; ok { sets = append(sets, "is_done=?"); if vb,ok2:=v.(bool); ok2 { if vb { args=append(args,1) } else { args=append(args,0) } } else { args=append(args, v) } }
    if v,ok := patch["orderIndex"]; ok { sets = append(sets, "order_index=?"); args = append(args, v) }
    if len(sets)==0 { return nil }
    args = append(args, itemID)
    _, err := s.db.ExecContext(ctx, `UPDATE issue_checklist_items SET `+strings.Join(sets, ", ")+` WHERE id=?`, args...)
    return err
}
func (s *sqliteIssueService) DeleteChecklistItem(ctx context.Context, itemID string) error {
    _, err := s.db.ExecContext(ctx, `DELETE FROM issue_checklist_items WHERE id=?`, itemID)
    return err
}

// Comments
func (s *sqliteIssueService) ListComments(ctx context.Context, issueID string) ([]map[string]interface{}, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT id,body,created_at FROM issue_comments WHERE issue_id=? ORDER BY created_at`, issueID)
    if err != nil { return nil, err }
    defer rows.Close()
    var out []map[string]interface{}
    for rows.Next(){ var id any; var body, created string; if err:=rows.Scan(&id,&body,&created); err!=nil { return nil, err }; out = append(out, map[string]interface{}{"id":id, "body":body, "createdAt":created}) }
    return out, nil
}
func (s *sqliteIssueService) AddComment(ctx context.Context, issueID, body string) (map[string]interface{}, error) {
    now := time.Now().UTC().Format(time.RFC3339)
    res, err := s.db.ExecContext(ctx, `INSERT INTO issue_comments(issue_id,author,body,created_at) VALUES (?,?,?,?)`, issueID, "", body, now)
    if err != nil { return nil, err }
    id, _ := res.LastInsertId()
    return map[string]interface{}{"id":id,"body":body,"createdAt":now}, nil
}
func (s *sqliteIssueService) DeleteComment(ctx context.Context, commentID string) error {
    _, err := s.db.ExecContext(ctx, `DELETE FROM issue_comments WHERE id=?`, commentID)
    return err
}

// Tags
func (s *sqliteIssueService) SetTagsBulk(ctx context.Context, issueID string, tags []string) error {
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil { return err }
    if _, err := tx.ExecContext(ctx, `DELETE FROM issue_tags WHERE issue_id=?`, issueID); err != nil { tx.Rollback(); return err }
    for _, t := range tags {
        if strings.TrimSpace(t) == "" { continue }
        if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO issue_tags(issue_id,tag) VALUES (?,?)`, issueID, t); err != nil { tx.Rollback(); return err }
    }
    return tx.Commit()
}
func (s *sqliteIssueService) DeleteTag(ctx context.Context, issueID, tag string) error {
    _, err := s.db.ExecContext(ctx, `DELETE FROM issue_tags WHERE issue_id=? AND tag=?`, issueID, tag)
    return err
}
