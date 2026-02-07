# flez-bot web site

Static site for **sign-up** and **password reset**. Uses your existing Supabase project; the desktop app signs in with the same accounts.

## Quick setup

1. **Copy the config and add your Supabase keys**
   ```bash
   cd web
   copy config.example.js config.js   # Windows
   # or: cp config.example.js config.js   # Mac/Linux
   ```
   Edit `config.js` and set:
   - `FLEZ_BOT_SUPABASE_URL` — your Supabase project URL (e.g. `https://xxxx.supabase.co`)
   - `FLEZ_BOT_SUPABASE_ANON_KEY` — your Supabase **anon** (public) key  
   - `FLEZ_BOT_DOWNLOAD_URL` — (optional) full URL to your **setup.exe** installer. If set, a “Download setup.exe” link appears on the index, signup, and reset-password pages. Use a GitHub Releases asset URL, or any URL where the exe is hosted (e.g. `https://github.com/YourOrg/flez-bot/releases/latest/download/setup.exe`).

   Use the same Supabase values as in the flez-bot root `.env` (SUPABASE_URL / SUPABASE_ANON_KEY). The anon key is safe to use in the browser.

2. **Run locally (optional)**
   ```bash
   npx serve .
   ```
   Then open http://localhost:3000/signup.html (or 5000, depending on `serve`).

   **Share with a tester on your network or over the internet:** Use a tunnel so they get a public URL. From the `web` folder (with `npx serve .` running in another terminal):
   ```bash
   npx ngrok http 3000
   ```
   Ngrok will show a URL like `https://abc123.ngrok.io`. Share that with your tester; they open e.g. `https://abc123.ngrok.io/signup.html`. Add the same URL to Supabase Redirect URLs (e.g. `https://abc123.ngrok.io/reset-password.html`). Set `FLEZ_BOT_SIGNUP_URL` and `FLEZ_BOT_PASSWORD_RESET_URL` in `.env` to the ngrok URLs while testing. (The URL changes each time you restart ngrok on the free tier.)

3. **Deploy the `web` folder** to any static host, for example:
   - **Vercel:** drag the `web` folder to [vercel.com](https://vercel.com) or connect your repo and set the root to `web`.
   - **Netlify:** connect the repo, set publish directory to `web`, deploy.
   - **GitHub Pages:** push the repo and set Pages to serve from the `web` directory (or a branch that contains only `web`).

   Ensure `config.js` is present in the deployed site (do **not** commit it if it contains secrets; use the host’s “environment” or “build” settings to inject the values, or keep a private `config.js` only on the server).

4. **Point the desktop app at your sign-up page**
   In the flez-bot root `.env` add:
   ```
   FLEZ_BOT_SIGNUP_URL=https://your-deployed-site.com/signup.html
   ```
   Use your real URL (e.g. `https://flez-bot.vercel.app/signup.html`). When users click “Sign up” in the desktop app, this URL is opened in the browser.

## Password reset redirect (Supabase)

So that “Forgot password” in the desktop app sends users to your site to set a new password:

1. In **Supabase Dashboard** go to **Authentication** → **URL Configuration**.
2. Add your reset page to **Redirect URLs**, e.g.:
   - `https://your-deployed-site.com/reset-password.html`
3. In **Authentication** → **Email Templates** → **Reset password**, set the redirect URL to that same `reset-password.html` URL (if your Supabase version has that field; otherwise the default link may use the first redirect URL).

Then when a user clicks “Forgot password” in the app and receives the email, the link in the email will bring them to your `reset-password.html` page to set a new password.

## Pages

| Page | Purpose |
|------|--------|
| `index.html` | Landing with sign up, reset password, and (if configured) Download setup.exe. |
| `signup.html` | Create account (email + password, optional display name). Use this URL for `FLEZ_BOT_SIGNUP_URL`. Includes download link when `FLEZ_BOT_DOWNLOAD_URL` is set. |
| `reset-password.html` | Set new password after clicking the link in the reset email. Add this URL to Supabase redirect URLs. Includes download link when set. |

After signing up or resetting, users sign in from the **flez-bot desktop app** (no need to sign in on the website).

---

## Getting a real setup.exe download URL

To host the installer so the site’s “Download setup.exe” link works:

### 1. Build the installer

From the **flez-bot repo root** (see **PACKAGING.md** for full details):

1. **Build the launcher exe**
   ```powershell
   pip install pyinstaller
   python -m PyInstaller flez-bot.spec
   copy dist\flez-bot.exe .
   ```
2. **Download bundled Git/Python installers**
   ```powershell
   .\installer_deps\download-installers.ps1
   ```
3. **Build the setup exe** (requires [Inno Setup](https://jrsoftware.org/isinfo.php) installed, `iscc` in PATH)
   ```powershell
   iscc installer.iss
   ```
   Output: **`dist\flez-bot-setup-0.1.0.exe`** (version comes from `installer.iss`).

### 2. Publish to GitHub Releases

1. On GitHub, open your repo → **Releases** → **Draft a new release**.
2. Choose a tag (e.g. `v0.1.0`) and title, add release notes.
3. **Attach** `dist\flez-bot-setup-0.1.0.exe` to the release (drag and drop or “Attach binaries”).
4. Publish the release.

**Download URL you can use:**

- **Versioned** (good for a specific release):
  ```text
  https://github.com/Roflz/flez-bot/releases/download/v0.1.0/flez-bot-setup-0.1.0.exe
  ```
  Replace `v0.1.0` and `flez-bot-setup-0.1.0.exe` with your tag and file name.

- **“Latest”** (always points at the newest release):  
  Upload the file with a **fixed name** (e.g. `setup.exe`) so the URL stays the same. Then use:
  ```text
  https://github.com/Roflz/flez-bot/releases/latest/download/setup.exe
  ```
  For each new release, upload the new build as `setup.exe` (replace the old asset or add it with the same name).

### 3. Set the URL in the web site

In **`web/config.js`** set:

```js
window.FLEZ_BOT_DOWNLOAD_URL = "https://github.com/Roflz/flez-bot/releases/latest/download/setup.exe";
```

(or the versioned URL above). Redeploy the web site (or refresh locally) so the “Download setup.exe” link uses the real installer.
