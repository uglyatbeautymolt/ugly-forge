---
name: brevo
description: "E-Mail senden via Brevo REST API. Aktiviert bei: Mail senden, E-Mail schreiben, Brevo, per E-Mail benachrichtigen, mailen."
---

# Brevo — E-Mail versenden

## Key — immer so lesen, nie suchen
```javascript
const apiKey = process.env.BREVO_KEY; // xkeysib-...
```
Kein Memory, kein TOOLS.md, kein Scan. Der Key liegt immer in der Umgebungsvariable.

## API-Call
```javascript
const response = await fetch("https://api.brevo.com/v3/smtp/email", {
  method: "POST",
  headers: {
    "api-key": process.env.BREVO_KEY,
    "Content-Type": "application/json"
  },
  body: JSON.stringify({
    sender: { name: "Ugly", email: "ugly@beautymolt.com" },
    to: [{ email: EMPFAENGER_EMAIL }],
    subject: BETREFF,
    textContent: TEXT
  })
});
const result = await response.json();
```

## Regeln
- Absender immer: `ugly@beautymolt.com` (Name: Ugly) — nie ändern
- Nur `textContent` verwenden, kein `htmlContent` sofern nicht explizit gewünscht
- Bei Fehler: `result.message` ausgeben
- Kein Retry ohne neue Nutzeranweisung
