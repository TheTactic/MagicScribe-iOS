# MagicScribe — App Store Connect submission drafts (iOS v1, Docs only)

Everything here describes only what the v1 binary does. No forms, Builder,
or Filler anywhere — iOS is strictly Docs.

Facts these drafts rely on (verified in code, 2026-11-27):
- Free: 10 dictation minutes/month, no AI refine, no Voice Edit.
- Voice Pro: 120 dictation minutes/month, AI refine, Voice Edit.
  US$12/month or US$108/year (auto-renewing).
- Dictation languages: English, Spanish, French.
- Formatting: bold/italic/underline, headings, alignment, font family/size/
  color, bulleted/numbered lists, undo/redo. Autosave. Image gallery per doc.
- No export/share in v1 — don't claim it.

---

## App name (30 max)

    MagicScribe: Voice Docs

(23 chars)

## Subtitle (30 max)

    Dictate, then edit by voice

(27 chars)

## Promotional text (170 max — editable any time without a new build)

    Dictate a document, then just say what to change: "Change Tuesday to Thursday." "Bold the word deadline." "Delete the last sentence." Done — no typing.

(153 chars)

## Keywords (100 max, comma-separated, no spaces needed)

    speech to text,dictate,transcribe,talk to text,voice typing,notes,writer,editor,hands free,AI,essay

(99 chars. Words already in the name/subtitle — "voice", "docs", "edit" —
are indexed automatically, so they aren't repeated here.)

## Description (4000 max)

    Write by talking — then edit by talking, too.

    Most dictation apps stop at turning speech into text. MagicScribe keeps going: once your words are on the page, you can tell it what to change, out loud, and it makes the edit for you.

    SAY WHAT TO CHANGE
    Tap Voice Edit and speak an instruction in plain language:
    • "Change Tuesday to Thursday."
    • "Bold every mention of the deadline."
    • "Delete the last sentence."
    • "Replace 'really good' with 'excellent'."
    MagicScribe's AI finds the right words anywhere in your document and makes the change — and if you don't like it, just say "undo that."

    FORMAT WITHOUT TOUCHING THE SCREEN
    Keep talking and drop in "magic" commands as you go:
    • "magic heading one" for a title
    • "magic bold on" … "magic bold off"
    • "magic new paragraph", "magic all caps", "magic undo"
    Commands are applied as formatting, never typed into your text.

    DICTATION THAT GETS IT RIGHT
    MagicScribe listens continuously and transcribes as you speak. An AI refine pass then cleans up each passage using the surrounding context — fixing misheard words and punctuation the way you meant them, and dropping the stray phrases speech recognition sometimes invents during pauses.

    A REAL DOCUMENT EDITOR
    • Bold, italic, underline, headings, and lists
    • Alignment, font, size, and color
    • Undo and redo
    • Attach images to any document
    • Autosave, so nothing gets lost
    • Dictate in English, Spanish, or French

    FREE TO START
    Create an account and get 10 minutes of dictation every month, free.

    VOICE PRO
    Upgrade to Voice Pro for 120 minutes of dictation a month, AI refine on everything you dictate, and Voice Edit.

    Voice Pro is an auto-renewing subscription, available monthly or yearly. Payment is charged to your Apple Account at confirmation of purchase. The subscription renews automatically unless cancelled at least 24 hours before the end of the current period, and your account is charged for renewal within 24 hours before the period ends. You can manage or cancel your subscription in your Apple Account settings at any time.

    Privacy Policy: https://magicscribe.tech/legal/privacy
    Terms of Use: https://magicscribe.tech/legal/terms

## Support URL / Marketing URL

- Support URL (required): needs a real page with a way to contact you.
  As of 2026-11-27, /support and /contact both 404 on production — a
  support page has to be created before submitting.
- Marketing URL (optional): https://magicscribe.tech
- Privacy Policy URL (required field in App Information):
  https://magicscribe.tech/legal/privacy

## Category

- Primary: Productivity
- Secondary: Business (or leave blank)

---

## App Review Information

### Demo account (create on PRODUCTION before submitting)

Reviewers need Voice Edit and AI refine, which are Voice Pro features, so
the demo account must already be on the voice_pro plan and email-verified —
otherwise they hit the paywall and can't see the app's core feature.

1. Sign up in the app (or on the web) with a dedicated address, e.g.
   appreview@magicscribe.tech, and verify it.
2. On the production DB, set users.plan = 'voice_pro' for that account.
3. Create one document titled "Sample document" with a few paragraphs,
   so Voice Edit has something to work on immediately. It MUST contain the
   words "Tuesday" and "deadline" — the reviewer notes tell them to say
   "Change Tuesday to Thursday" and "Bold the word deadline". E.g.:
   "The project kickoff is on Tuesday. Please review the plan before the
   deadline. Our team did really good work this quarter."

Voice Edit supports only: bold/italic/underline exact text, delete text,
replace text, delete a line, and undo/redo. Don't promise rewrites,
tone changes, or list conversion anywhere in the listing.

### Notes for the reviewer

    Thank you for reviewing MagicScribe.

    MagicScribe is a voice-first document editor. Beyond dictation, its core feature is Voice Edit: the user speaks an instruction about their document in plain language, and the app edits the document accordingly.

    The demo account below is already on the Voice Pro plan, so every feature is unlocked without a purchase.

    Suggested 1-minute walkthrough:
    1. Sign in with the demo account and open "Sample document".
    2. Tap Dictate and speak a sentence or two. Try saying "magic new paragraph" or "magic bold on" mid-sentence — these are applied as formatting, not typed as text. Tap Dictate again to stop.
    3. Tap Voice Edit and say: "Change Tuesday to Thursday." The sample document is edited in place. Then tap Voice Edit again and say "Bold the word deadline." Saying "undo that" (or tapping Undo) reverts an edit.

    Account deletion: My Docs > "..." (top left) > Delete Account.
    Restore Purchases: My Docs > "..." > Restore Purchases.

    Audio is sent to our server for transcription; text is processed by AI only to transcribe, refine, and apply edits the user requests. Nothing is shared for advertising or tracking.

    Demo account:
    Email: [fill in]
    Password: [fill in]

---

## Age rating questionnaire

Answer "None" / "No" to everything: no violence, sexual content, profanity,
drugs, gambling, horror, medical info, unrestricted web access, user-to-user
communication, or contests. The app doesn't let users share content with
other users. Expected result: 4+.

If asked whether the app includes AI-generated content: the AI only rewrites
the user's own text at their request — answer per that description.

---

## App Privacy ("nutrition label")

Tracking: **No** — the app doesn't track users across other companies' apps
or websites, and has no ad or analytics SDKs.

Data collected — all **linked to the user**, all for **App Functionality**
only, none used for tracking:

| Data type | Apple category | Why |
|---|---|---|
| Email address | Contact Info | Account sign-in and verification emails |
| Name | Contact Info | Entered at signup |
| Audio data | User Content | Sent to the server for transcription (OpenAI) |
| Other user content | User Content | Document text (stored; processed by Anthropic for refine/Voice Edit) |
| Photos | User Content | Images attached to documents (stored on the server) |
| Purchase history | Purchases | Verifying the Voice Pro subscription |
| User ID | Identifiers | Account identifier |

Third-party processors the backend sends data to (list in your privacy
policy, not in the label itself): OpenAI (speech-to-text), Anthropic
(refine, Voice Edit), SendGrid (verification emails), Apple (purchase
verification).

---

## Screenshots (to do next)

Required: 6.9" iPhone (1320 x 2868 or 1290 x 2796). iPad screenshots only
if the app is offered on iPad.

Planned order — lead with what no plain dictation app does:
1. Voice Edit mid-edit: instruction shown, document changing
2. Before/after of a Voice Edit
3. Dictation in progress with "magic" formatting commands applied
4. Formatting sheet (fonts, color, lists, alignment)
5. A polished finished document
6. My Docs list
