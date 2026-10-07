# Optional learning mode

`project.settings.json` contains `"learningMode": false` by default.
This is a collaboration preference, independent of provider and the developer's age.

Say "Enable learning mode" or "Disable learning mode" to the assistant, or edit the boolean.
The assistant updates it immediately, keeps other settings, and briefly confirms the change.
Use the current request immediately and re-read the file at session start. False restores
adult collaboration; no lesson framing, language-practice prompts or forced simplification.

When enabled:
- Use short, simple, respectful language; normally one question at a time.
- Invite typed answers about the game. Give a small example if the developer is stuck.
- Support reading/writing through making the game, never as a lesson or spelling correction.
- Understand spelling silently and naturally use correct wording.
- Adjust support to the developer's current needs without assuming age or ability.
- Occasional guest messages do not imply a lasting preference change.
- Own technical decisions and troubleshooting; preserve the same approval/polish/QA standards.

Both modes keep short brainstorming, feature bundles and concise progress/outcome messages.
