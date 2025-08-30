// Package main является точкой входа в приложение.
package main

import (
	"log"
	"net/http"

	"potok/backend/internal/db"
	"potok/backend/internal/server"
	"potok/backend/internal/store"
)

// main - точка входа в приложение.
func main() {
	// 1. Инициализируем базу данных.
	database, err := db.InitDB("./potok.db")
	if err != nil {
		log.Fatalf("не удалось инициализировать БД: %v", err)
	}
	defer database.Close()

	// 2. Создаем экземпляр хранилища, передавая ему подключение к БД.
	appStore := store.New(database)

	// 3. Создаем экземпляр HTTP-сервера, передавая ему хранилище.
	httpServer := server.New(appStore)

	// 4. Настраиваем и запускаем HTTP-сервер.
	log.Printf("сервер слушает порт :8080")
	if err := http.ListenAndServe(":8080", httpServer); err != nil {
		log.Fatalf("ошибка при запуске сервера: %v", err)
	}
}