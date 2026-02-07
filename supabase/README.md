# Supabase setup for flez-bot (Option A)

## 1. Create a project

1. Go to [supabase.com](https://supabase.com) and sign in (or create an account).
2. Click **New project**.
3. Pick your organization, name the project (e.g. `flez-bot`), set a **Database password** (store it in a password manager), choose a region, then click **Create new project**.
4. Wait for the project to finish provisioning.

## 2. Enable Authentication (Email)

Email + password sign-in is **on by default**. You only need to confirm and optionally tweak it:

1. In the left sidebar, open **Authentication**.
2. Click **Providers**.
3. Find **Email** in the list — it should already be **Enabled**.
4. Optional:
   - **Confirm email**: If enabled, users must click a link in their email before they can sign in. For local/dev you can turn this off so sign-in works immediately.
   - **Allow new user sign ups**: Leave on if you want the app’s “Sign up” to create new accounts.

No need to enable “Magic Link” or “Email OTP” unless you want passwordless login; flez-bot uses **email + password**.

## 3. Run the profiles migration

1. In the left sidebar, open **SQL Editor**.
2. Click **New query**.
3. Open the file **`supabase/migrations/001_profiles.sql`** in this repo, copy its contents, and paste into the editor.
4. Click **Run** (or press Ctrl+Enter).
5. You should see “Success. No rows returned.” The `profiles` table and trigger are now created.

## 4. Get your project URL and anon key

1. In the left sidebar, click **Project Settings** (gear icon).
2. **Project URL:** On **Data API** (or **API**), copy the **URL** at the top (e.g. `https://xxxx.supabase.co`) → use as `SUPABASE_URL`.
3. **Anon key:** In the same left sub-menu, click **API Keys**. Under "Project API keys", find the key named **anon** and labeled **public** — click to reveal/copy it → use as `SUPABASE_ANON_KEY`.

## 5. Configure the app (where to put the API keys)

Put the keys in a **`.env` file in the flez-bot project root** (the folder that contains `launcher.py`, `setup.ps1`, and the `bot_runelite_IL` folder). The launcher loads that file on startup.

1. In the project root, create a file named `.env` (no extension).
2. Add these lines (use your real URL and key from step 4):

   ```
   SUPABASE_URL=https://xxxx.supabase.co
   SUPABASE_ANON_KEY=your_anon_key_here
   ```

3. Save the file. **Do not commit `.env` to git** — it's already in `.gitignore`.

Alternatively you can set `SUPABASE_URL` and `SUPABASE_ANON_KEY` as system or user environment variables in Windows; the app reads them the same way.

Optional in `.env`:

- **`FLEZ_BOT_SIGNUP_URL`** — URL for “Sign up”. Sign-up is done on the website, not in-app. Set this to your sign-up page. You can use the static site in this repo’s **`web/`** folder: see **`web/README.md`** for setup (copy `config.example.js` to `config.js`, add your Supabase URL and anon key, then deploy the `web` folder to Vercel/Netlify/etc. and set `FLEZ_BOT_SIGNUP_URL` to e.g. `https://yoursite.com/signup.html`).

**Forgot password** is handled in-app: the user enters their email and clicks “Forgot password”; the app sends a reset link via Supabase. No separate URL is required.

### Subscription tier (free / paid)

The `profiles` table has a `subscription_tier` column (`'free'` or `'paid'`). The Home tab shows **Plan: Free** or **Plan: Paid** and an “Upgrade” / “Manage subscription” button. To grant a user paid access, update their row in Supabase (e.g. Table Editor or SQL):

```sql
update public.profiles set subscription_tier = 'paid' where user_id = '<user-uuid>';
```

You can later wire this to Stripe or another payment provider; the app uses `auth.session.is_paid()` to gate paid-only features.

After this, the app will show the login dialog on startup when Supabase is configured; users can sign in, and the Home tab will show their profile (display name, masked email, plan), **Edit profile**, **Sign out** (which shows the login dialog again instead of closing the app), and optional **Stay logged in**.
