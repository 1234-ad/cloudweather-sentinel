#!/usr/bin/env python3
"""
AI Weather Predictor Service
Uses machine learning to predict weather patterns
"""

import os
import json
import logging
import asyncio
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import numpy as np
import pandas as pd
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
from prometheus_client import Counter, Histogram, generate_latest
from prometheus_client.exposition import make_wsgi_app
from sklearn.ensemble import RandomForestRegressor
from sklearn.preprocessing import StandardScaler
import joblib

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('ai_predictor_requests_total', 'Total requests')
PREDICTION_TIME = Histogram('ai_predictor_prediction_seconds', 'Time spent on predictions')
MODEL_ACCURACY = Histogram('ai_predictor_model_accuracy', 'Model prediction accuracy')

class WeatherInput(BaseModel):
    location: str
    current_temp: float
    humidity: int
    pressure: float
    wind_speed: float
    historical_data: Optional[List[Dict]] = None

class WeatherPrediction(BaseModel):
    location: str
    predicted_temp: float
    confidence: float
    forecast_hours: int
    timestamp: datetime
    model_version: str

class AIWeatherPredictor:
    def __init__(self):
        self.model = None
        self.scaler = StandardScaler()
        self.model_version = "1.0.0"
        self.is_trained = False
        self._initialize_model()

    def _initialize_model(self):
        """Initialize the ML model"""
        try:
            # Try to load pre-trained model
            if os.path.exists('model.joblib'):
                self.model = joblib.load('model.joblib')
                self.scaler = joblib.load('scaler.joblib')
                self.is_trained = True
                logger.info("Loaded pre-trained model")
            else:
                # Create new model
                self.model = RandomForestRegressor(
                    n_estimators=100,
                    random_state=42,
                    max_depth=10
                )
                self._train_dummy_model()
                logger.info("Created new model with dummy data")
        except Exception as e:
            logger.error(f"Error initializing model: {e}")
            self.model = RandomForestRegressor(n_estimators=50, random_state=42)

    def _train_dummy_model(self):
        """Train model with synthetic data for demo purposes"""
        # Generate synthetic training data
        np.random.seed(42)
        n_samples = 1000
        
        # Features: temp, humidity, pressure, wind_speed, hour_of_day
        X = np.random.rand(n_samples, 5)
        X[:, 0] = X[:, 0] * 40 - 10  # Temperature: -10 to 30°C
        X[:, 1] = X[:, 1] * 100      # Humidity: 0-100%
        X[:, 2] = X[:, 2] * 100 + 950  # Pressure: 950-1050 hPa
        X[:, 3] = X[:, 3] * 20       # Wind speed: 0-20 m/s
        X[:, 4] = X[:, 4] * 24       # Hour of day: 0-24
        
        # Target: next hour temperature (with some pattern)
        y = X[:, 0] + 0.1 * X[:, 1] - 0.05 * X[:, 2] + np.random.normal(0, 2, n_samples)
        
        # Scale features
        X_scaled = self.scaler.fit_transform(X)
        
        # Train model
        self.model.fit(X_scaled, y)
        self.is_trained = True
        
        # Save model
        joblib.dump(self.model, 'model.joblib')
        joblib.dump(self.scaler, 'scaler.joblib')
        
        logger.info("Model trained with synthetic data")

    async def predict_weather(self, weather_input: WeatherInput) -> WeatherPrediction:
        """Predict weather for next few hours"""
        with PREDICTION_TIME.time():
            if not self.is_trained:
                raise HTTPException(status_code=503, detail="Model not trained")
            
            try:
                # Prepare features
                current_hour = datetime.now().hour
                features = np.array([[
                    weather_input.current_temp,
                    weather_input.humidity,
                    weather_input.pressure,
                    weather_input.wind_speed,
                    current_hour
                ]])
                
                # Scale features
                features_scaled = self.scaler.transform(features)
                
                # Make prediction
                predicted_temp = self.model.predict(features_scaled)[0]
                
                # Calculate confidence (simplified)
                confidence = min(0.95, max(0.6, 1.0 - abs(predicted_temp - weather_input.current_temp) / 10))
                
                return WeatherPrediction(
                    location=weather_input.location,
                    predicted_temp=round(predicted_temp, 2),
                    confidence=round(confidence, 3),
                    forecast_hours=1,
                    timestamp=datetime.now(),
                    model_version=self.model_version
                )
                
            except Exception as e:
                logger.error(f"Prediction error: {e}")
                raise HTTPException(status_code=500, detail="Prediction failed")

# Initialize FastAPI app
app = FastAPI(
    title="AI Weather Predictor",
    description="Machine Learning Weather Prediction Service",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize predictor
predictor = AIWeatherPredictor()

@app.post("/predict", response_model=WeatherPrediction)
async def predict_weather(weather_input: WeatherInput):
    """Predict weather based on current conditions"""
    REQUEST_COUNT.inc()
    return await predictor.predict_weather(weather_input)

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "ai-predictor",
        "model_trained": predictor.is_trained,
        "model_version": predictor.model_version,
        "timestamp": datetime.now().isoformat()
    }

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

@app.get("/model/info")
async def model_info():
    """Get model information"""
    return {
        "model_type": "RandomForestRegressor",
        "version": predictor.model_version,
        "trained": predictor.is_trained,
        "features": ["temperature", "humidity", "pressure", "wind_speed", "hour_of_day"]
    }

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8081))
    uvicorn.run(app, host="0.0.0.0", port=port)