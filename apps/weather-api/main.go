package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type WeatherData struct {
	Location    string    `json:"location"`
	Temperature float64   `json:"temperature"`
	Humidity    int       `json:"humidity"`
	Pressure    float64   `json:"pressure"`
	WindSpeed   float64   `json:"wind_speed"`
	Timestamp   time.Time `json:"timestamp"`
	Source      string    `json:"source"`
}

type WeatherService struct {
	requestCounter prometheus.Counter
	responseTime   prometheus.Histogram
}

func NewWeatherService() *WeatherService {
	return &WeatherService{
		requestCounter: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "weather_api_requests_total",
			Help: "Total number of weather API requests",
		}),
		responseTime: prometheus.NewHistogram(prometheus.HistogramOpts{
			Name: "weather_api_response_time_seconds",
			Help: "Response time for weather API requests",
		}),
	}
}

func (ws *WeatherService) GetWeather(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	ws.requestCounter.Inc()

	vars := mux.Vars(r)
	location := vars["location"]

	// Simulate weather data (in real implementation, fetch from external APIs)
	weather := WeatherData{
		Location:    location,
		Temperature: 22.5 + float64(time.Now().Unix()%10),
		Humidity:    65 + int(time.Now().Unix()%20),
		Pressure:    1013.25,
		WindSpeed:   5.2,
		Timestamp:   time.Now(),
		Source:      "CloudWeather-Sentinel-API",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(weather)

	ws.responseTime.Observe(time.Since(start).Seconds())
}

func (ws *WeatherService) HealthCheck(w http.ResponseWriter, r *http.Request) {
	response := map[string]string{
		"status":    "healthy",
		"service":   "weather-api",
		"timestamp": time.Now().Format(time.RFC3339),
		"version":   "1.0.0",
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func main() {
	ws := NewWeatherService()
	
	// Register Prometheus metrics
	prometheus.MustRegister(ws.requestCounter)
	prometheus.MustRegister(ws.responseTime)

	r := mux.NewRouter()
	
	// API routes
	r.HandleFunc("/weather/{location}", ws.GetWeather).Methods("GET")
	r.HandleFunc("/health", ws.HealthCheck).Methods("GET")
	r.Handle("/metrics", promhttp.Handler())

	// CORS middleware
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
			next.ServeHTTP(w, r)
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Weather API starting on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, r))
}