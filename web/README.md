# flez-bot web site

Static site for **sign-up** and **password reset**. The desktop app and this site share one config: `web/config.js`.

## Config

Edit **`config.js`** (single source of truth; desktop app reads it too):

- `FLEZ_BOT_SUPABASE_URL` — Supabase project URL
- `FLEZ_BOT_SUPABASE_ANON_KEY` — Supabase anon (public) key
- `FLEZ_BOT_SITE_URL` — Base URL of this site (e.g. `https://flez-bot.vercel.app`). Sign-up and reset URLs are derived from it.
- `FLEZ_BOT_DOWNLOAD_URL` — Full URL to setup.exe (e.g. `https://github.com/Roflz/flez-bot/releases/latest/download/setup.exe`). If set, a “Download setup.exe” link appears on the pages.

## Run locally

```bash
cd web
npx serve .
```

Open http://localhost:3000/signup.html (or the port `serve` reports).

## Deploy

Deploy the `web` folder to any static host (e.g. Vercel, Netlify, GitHub Pages). Ensure `config.js` is deployed with your values.

## Password reset (Supabase)

1. **Supabase Dashboard** → **Authentication** → **URL Configuration**
2. Add to **Redirect URLs**: `https://your-site.com/reset-password.html`
3. Set **Site URL** to your base URL with no leading/trailing spaces.

The Reset password email template should use `{{ .ConfirmationURL }}` for the link.

## Pages

| Page | Purpose |
|------|--------|
| `index.html` | Landing: sign up, reset password, download link (if configured). |
| `signup.html` | Create account (email + password, optional display name). |
| `reset-password.html` | Set new password after clicking the link in the reset email. |

Users sign in from the **flez-bot desktop app**.

## setup.exe download URL

- **Latest release:** Upload the installer as `setup.exe` to each GitHub release and use:
  ```text
  https://github.com/Roflz/flez-bot/releases/latest/download/setup.exe
  ```
- Set this in `config.js` as `FLEZ_BOT_DOWNLOAD_URL`. Redeploy the site after changing config.
