// Package main является точкой входа в приложение.
package main

import (
	"log/slog"
	"net/http"
	"os"
	"potok/backend/internal/db"
	"potok/backend/internal/server"
	"potok/backend/internal/store"
)

// main - точка входа в приложение.
func main() {
	// Настраиваем глобальный логгер slog
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		AddSource: true,
		Level:     slog.LevelInfo,
	})))
	// 1. Инициализируем базу данных.
	database, err := db.InitDB("./potok.db")
	if err != nil {
		slog.Error("Ошибка: не удалось инициализировать БД", "error", err)
		os.Exit(1)
	}
	slog.Info("База данных успешно инициализирована.")
	defer func() {
		database.Close()
		slog.Info("Соединение с базой данных закрыто.")
	}()

	// 2. Создаем экземпляр хранилища, передавая ему подключение к БД.
	appStore := store.New(database)

	// 3. Создаем экземпляр HTTP-сервера, передавая ему хранилище.
	httpServer := server.New(appStore)

	// 4. Настраиваем и запускаем HTTP-сервер.
	slog.Info("Сервер запускается и слушает порт :8080", "port", 8080)
	if err := http.ListenAndServe(":8080", httpServer); err != nil {
		slog.Error("Критическая ошибка: сервер завершил работу с ошибкой", "error", err)
		os.Exit(1)
	}
	slog.Info("Приложение завершило работу.")
}
