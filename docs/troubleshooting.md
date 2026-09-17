# Troubleshooting

**The menu bar shows "—"**
No limit is selected yet, or the selected provider is disconnected. Open the
panel: a disconnected provider shows the reason in place of its rows. Click a row
to make it the menu bar figure.

**"Not signed in to Claude Code"**
The app found no Claude Code credentials. Run `claude` in a terminal and sign in
with your subscription, then press Refresh in the panel.

**"Sign in with ChatGPT" for the ChatGPT provider**
`~/.codex/auth.json` holds an API-key-only login. Run `codex login` and choose the
ChatGPT sign-in; API keys carry no subscription limits.

**macOS keeps asking for keychain access**
The Claude provider reads Claude Code's keychain item through `security`. Choose
**Always Allow** in the prompt. If Claude Code rewrites the item (for example
after a re-login), macOS may ask once more.

**"Start at login" is on but the app doesn't start, or the wrong copy starts**
The login item points at the app bundle that registered it. If you moved or
reinstalled the app, open the panel, turn the checkbox off and on again from the
installed copy. You can also inspect it under System Settings → General →
Login Items.

**Gatekeeper says the app is damaged or from an unidentified developer**
Only unsigned builds do this. Releases from the Releases page and the Homebrew
cask are signed and notarized; a build you made yourself from Xcode is not.
