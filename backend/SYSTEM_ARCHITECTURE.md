# System Architecture

```mermaid
flowchart LR
    A[Flutter App] --> B[Audio Capture Service]
    B --> C[Backend API Service]
    C --> D[/recognize Flask Route]
    D --> E[Recognition Service]
    E --> F[Audio Preprocessing]
    F --> G[Feature Extraction]
    G --> H[Song Matcher]
    H --> I[(Feature Matrix)]
    E --> J[(SQLite Logs)]
    E --> K[Structured JSON Response]
    K --> A
    A --> L[Spotify Auth Service]
    L --> M[Spotify Playlist Service]
    M --> N[Spotify Web API]
```

# Sequence Flow

```mermaid
sequenceDiagram
    participant U as User
    participant F as Flutter App
    participant B as Flask Backend
    participant R as Recognition Service
    participant M as Matcher
    participant S as Spotify API

    U->>F: Tap microphone
    F->>F: Record 10-second clip
    F->>B: POST /recognize (audio + recording_time_ms)
    B->>R: recognize(audio)
    R->>R: preprocess_audio()
    R->>R: extract_features()
    R->>M: match_features()
    M-->>R: best match + top 3 candidates
    R->>R: log result to SQLite
    R-->>B: structured response
    B-->>F: status, confidence, timings, suggestions
    alt confidence >= 0.8
        F->>S: Search track and add to playlist
        S-->>F: Playlist update success/failure
    else 0.5 <= confidence < 0.8
        F->>U: Ask for confirmation
        U->>F: Confirm suggested track
        F->>S: Add selected song to playlist
    else confidence < 0.5
        F->>U: Show top 3 suggestions or retry
    end
```
