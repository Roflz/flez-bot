# flez-bot

Umbrella repository that bundles the bot (bot_runelite_IL) and RuneLite (runelite) as Git submodules for a single clone-and-run setup.

## Quick start

```powershell
# 1. Clone the umbrella repo
git clone https://github.com/Roflz/flez-bot.git
cd flez-bot

# 2. Run setup (installs prerequisites if needed, inits submodules, runs dependency setup)
.\setup.ps1

# 3. Add credentials and run the launcher
# Add your .properties files to bot_runelite_IL\credentials\
cd bot_runelite_IL
python gui_pyside.py
```

## Requirements

- **Windows** (PowerShell 5.1+)
- **Git** – installed by setup if missing (via Chocolatey)
- **Python 3** – installed by setup if missing (via Chocolatey)
- **Java JDK 11** – installed by `setup-dependencies.ps1` (run by setup)
- **Chocolatey** (recommended) – used to install Git, Python, Java; [install](https://chocolatey.org/install) as Administrator if needed

## Repository layout

```
flez-bot/
├── setup.ps1              # Run this first
├── README.md
├── .gitmodules
├── bot_runelite_IL/       # Submodule (branch: main)
└── runelite/              # Submodule (branch: master, your fork)
```

- **bot_runelite_IL**: Bot GUI, plans, and launcher logic. Branch: `main`.
- **runelite**: Your RuneLite fork. Branch: `master`. The launcher fetches upstream releases when you launch instances.

## Updating submodules

To pull the latest bot and runelite changes:

```powershell
git submodule update --remote
git submodule update --init --recursive
```

Then in each submodule you can `git pull` as usual.

## Troubleshooting

- **"Git not found"** – Install [Git](https://git-scm.com/) or run `choco install git -y` (as Administrator).
- **"Python 3 not found"** – Install [Python 3](https://www.python.org/) or run `choco install python -y`.
- **Java / Maven errors** – Run `bot_runelite_IL\setup-dependencies.ps1` as Administrator, or install [Java JDK 11](https://adoptium.net/) and [Maven](https://maven.apache.org/) manually.
- **Submodules empty** – Run `git submodule update --init --recursive` from the umbrella repo root.

## For repository maintainers

One-time setup of this umbrella repo (already done for this repo):

1. Create GitHub repo `flez-bot` (e.g. with a README).
2. Clone it, then add submodules:
   ```powershell
   git clone https://github.com/Roflz/flez-bot.git
   cd flez-bot
   git submodule add -b main https://github.com/Roflz/bot_runelite_IL.git bot_runelite_IL
   git submodule add -b master https://github.com/Roflz/runelite.git runelite
   ```
3. Add `setup.ps1`, `README.md`, `.gitignore` (and this README), then commit and push.
