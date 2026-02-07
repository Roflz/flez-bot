These installers are bundled into setup.exe so Git and Python can be installed without winget.

Before building the installer (iscc installer.iss), run:

  .\installer_deps\download-installers.ps1

That downloads the official Git and Python installers and saves them as
GitInstaller.exe and PythonInstaller.exe. The installer then runs them
silently when the user doesn't have Git or Python.

You can also download manually and rename:
  - Git: https://git-scm.com/download/win  -> save as GitInstaller.exe
  - Python 3.13 64-bit: https://www.python.org/downloads/  -> save as PythonInstaller.exe
