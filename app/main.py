from fastapi import FastAPI

app = FastAPI(title= "Cloud Operations Portal", description="A portal for managing cloud operations", version="1.0.0")

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/")
def root():
    return {"message": "Cloud Operations Portal API"}

