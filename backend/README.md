# English Word App Backend

This backend keeps the OpenAI API key on the server side and exposes a small API for the iPhone app.

## Setup

1. Install dependencies:

```bash
npm install
```

2. Create an environment file:

```bash
cp .env.example .env
```

3. Set your `OPENAI_API_KEY` in `.env`.

4. Start the server:

```bash
npm run dev
```

The backend runs on `http://localhost:3000` by default.

## App Configuration

Set this in your Xcode scheme environment variables or app configuration:

```text
WORD_ENTRY_API_BASE_URL=http://localhost:3000
```

For a simulator, `localhost` points to your Mac. For a physical iPhone, use your Mac's local IP or deploy this backend to a hosted server with HTTPS.

## Endpoints

- `GET /health`
- `POST /v1/word-entry`

Example request:

```json
{
  "word": "apple"
}
```
