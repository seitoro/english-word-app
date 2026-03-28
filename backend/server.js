import "dotenv/config";
import express from "express";
import cors from "cors";

const app = express();
const port = Number(process.env.PORT || 3000);
const openAIKey = process.env.OPENAI_API_KEY;
const model = process.env.OPENAI_MODEL || "gpt-5.4-mini";

app.use(cors());
app.use(express.json());

app.get("/health", (_request, response) => {
  response.json({
    ok: true,
    model,
    openAIConfigured: Boolean(openAIKey)
  });
});

app.post("/v1/word-entry", async (request, response) => {
  try {
    const word = String(request.body?.word || "").trim();
    if (!word) {
      return response.status(400).json({ error: "word is required" });
    }

    if (!openAIKey) {
      return response.status(500).json({ error: "OPENAI_API_KEY is not configured" });
    }

    const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openAIKey}`
      },
      body: JSON.stringify({
        model,
        instructions: [
          "You create vocabulary notebook entries for Japanese learners.",
          "The target may be a single English word or a short English phrase/idiom.",
          "Return valid JSON only with these keys:",
          "word, senses, contextualMeanings",
          "Keep word exactly equal to the input word.",
          "senses must be an array of the common meanings of the word or phrase for learners.",
          "Each item in senses must have these keys:",
          "partOfSpeech, meaningJapanese, exampleSentence, exampleTranslation",
          "For phrases and idioms, include the representative meaning learners should memorize first.",
          "Include as many common meanings as are useful, up to 6 senses.",
          "meaningJapanese should be short and natural.",
          "exampleSentence should be one simple English sentence using the word for that meaning.",
          "exampleTranslation should be the natural Japanese translation of the example sentence.",
          "partOfSpeech should be short, such as noun, verb, adjective, adverb, preposition.",
          "Do not include duplicate senses.",
          "contextualMeanings must be an array with up to 3 items showing how meaning changes by sentence or context.",
          "Each item in contextualMeanings must have these keys:",
          "sentence, sentenceTranslation, meaningJapanese, explanationJapanese",
          "Use contextualMeanings for polysemous words and idiomatic phrases. Return an empty array only if there is truly no useful variation to show.",
          "sentence should be a natural English sentence.",
          "sentenceTranslation should be the natural Japanese translation of that sentence.",
          "meaningJapanese should be the meaning in that sentence.",
          "explanationJapanese should briefly explain why the meaning changes in that context."
        ].join("\n"),
        input: `Target word or phrase: ${word}\nReturn exactly one JSON object.`,
        reasoning: { effort: "low" }
      })
    });

    if (!openAIResponse.ok) {
      const errorText = await openAIResponse.text();
      let message = "OpenAI request failed";

      if (errorText.includes("insufficient_quota")) {
        message = "OpenAI quota is not available";
      }

      return response.status(502).json({ error: message, details: errorText });
    }

    const data = await openAIResponse.json();
    const text = data.output_text || firstText(data.output);
    const payload = extractJSONObject(text);

    return response.json({
      word: payload.word,
      senses: Array.isArray(payload.senses) ? payload.senses : [],
      contextualMeanings: Array.isArray(payload.contextualMeanings) ? payload.contextualMeanings : [],
      generatedBy: "OpenAI via Secure Backend"
    });
  } catch (error) {
    return response.status(500).json({
      error: "Failed to generate word entry",
      details: error instanceof Error ? error.message : "Unknown error"
    });
  }
});

app.listen(port, () => {
  console.log(`English word backend listening on http://localhost:${port}`);
});

function firstText(output = []) {
  for (const item of output) {
    for (const content of item.content || []) {
      if (content.text) {
        return content.text;
      }
    }
  }

  return null;
}

function extractJSONObject(text) {
  if (typeof text !== "string") {
    throw new Error("OpenAI returned no text response");
  }

  const trimmed = text.trim();
  if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
    return JSON.parse(trimmed);
  }

  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start === -1 || end === -1 || start > end) {
    throw new Error("Could not extract JSON object from model response");
  }

  return JSON.parse(trimmed.slice(start, end + 1));
}
