package main

import (
	"log/slog"
	"net/http"
	"os"

	mailhttp "potok/backend/internal/mail/http"
	"potok/backend/internal/mail/provider"
	"potok/backend/internal/mail/service"
)

func main() {
	// Настраиваем глобальный логгер slog
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		AddSource: true,
		Level:     slog.LevelInfo,
	})))

	slog.Info("Запуск сервера модуля 'Почта'...")

	// Создаем фабрику провайдеров
	providerFactory := provider.NewProviderFactory()

	// Создаем сервисы
	accountService := service.NewAccountService(providerFactory)
	threadService := service.NewThreadService(providerFactory)
	sendService := service.NewSendService(providerFactory)

	// Создаем HTTP роутер
	router := mailhttp.NewRouter(accountService, threadService, sendService)

	// Настраиваем и запускаем HTTP-сервер
	port := ":8081" // Отдельный порт для модуля "Почта"
	slog.Info("Сервер модуля 'Почта' запускается", "port", port)

	if err := http.ListenAndServe(port, router); err != nil {
		slog.Error("Критическая ошибка: сервер завершил работу", "error", err)
		os.Exit(1)
	}
}
