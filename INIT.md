# One-time setup for repository maintainers

Use these steps once to create and push the umbrella repository (including submodules).

## Option A: You already have this folder (e.g. `D:\repos\flez-bot`)

1. Create a new **empty** repository on GitHub named `flez-bot` (no README, no .gitignore).

2. In this folder, initialize Git and add the remote:
   ```powershell
   cd D:\repos\flez-bot
   git init
   git remote add origin https://github.com/Roflz/flez-bot.git
   ```

3. Add submodules (this creates `bot_runelite_IL` and `runelite` and updates `.gitmodules`):
   ```powershell
   git submodule add -b main https://github.com/Roflz/bot_runelite_IL.git bot_runelite_IL
   git submodule add -b master https://github.com/Roflz/runelite.git runelite
   ```

4. Commit and push (use `main` as default branch):
   ```powershell
   git add .
   git commit -m "Initial umbrella repository setup"
   git branch -M main
   git push -u origin main
   ```

## Option B: You clone the GitHub repo first

1. Create a new **empty** repository on GitHub named `flez-bot`.

2. Clone it and go into it:
   ```powershell
   git clone https://github.com/Roflz/flez-bot.git
   cd flez-bot
   ```

3. Copy into this clone the files: `setup.ps1`, `README.md`, `.gitignore`, `.gitmodules` (from the folder where they were created).

4. Add submodules:
   ```powershell
   git submodule add -b main https://github.com/Roflz/bot_runelite_IL.git bot_runelite_IL
   git submodule add -b master https://github.com/Roflz/runelite.git runelite
   ```

5. Commit and push:
   ```powershell
   git add .
   git commit -m "Initial umbrella repository setup"
   git push origin main
   ```

After this, anyone can clone and run:

```powershell
git clone https://github.com/Roflz/flez-bot.git
cd flez-bot
.\setup.ps1
```
