package service

import "context"

type DeltaPatch struct {
    Type      string      `json:"type"`
    Entity    string      `json:"entity"`
    Data      interface{} `json:"data,omitempty"`
    UID       *string     `json:"uid,omitempty"`
    DeletedAt *string     `json:"deletedAt,omitempty"`
}

type SyncService interface {
    Delta(ctx context.Context, anchor string, limit int, cursor string) ([]DeltaPatch, *string, string, error)
}

type NoopSyncService struct{}

func (s NoopSyncService) Delta(ctx context.Context, anchor string, limit int, cursor string) ([]DeltaPatch, *string, string, error) {
    newAnchor := anchor
    return []DeltaPatch{}, nil, newAnchor, nil
}

