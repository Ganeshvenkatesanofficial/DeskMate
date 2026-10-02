# DeskMate Desktop User Guide & Complete Google Setup

Welcome to **DeskMate**, your local offline AI Desktop Copilot and Personal Assistant!

---

## 🚀 Quick Start (Running DeskMate)

1. **Extract** the entire ZIP folder onto your computer.
2. Double-click **`DeskMate.exe`**.
   * *Note: DeskMate automatically launches its silent local AI backend process in the background. No console prompts or black windows will appear.*
3. Paste your **Gemini API Key** in the sidebar configuration and click **Load Key**.
4. You can now toggle between **File Explorer** and **Personal Agent** modes instantly!

---

## 🔐 Complete Step-by-Step Google Setup Guide

To enable **Gmail, Calendar, Drive & Tasks** integrations and get all **PERSONAL SERVICES HEALTH** checkmarks green, follow these exact steps:

### Step 1: Open Google Cloud Console
1. Open your web browser and go to [https://console.cloud.google.com/](https://console.cloud.google.com/).
2. Sign in with your Google account.

### Step 2: Create a New Project
1. At the top navigation bar (next to the Google Cloud logo), click the **Project Dropdown**.
2. Click **New Project** in the top-right of the modal window.
3. Enter a Project Name (e.g. `DeskMate Personal Agent`).
4. Click **Create** and wait a few seconds for Google to finish setting it up.

### Step 3: Enable the 4 Required APIs
1. On the left sidebar, click **APIs & Services** -> **Library** (or visit [https://console.cloud.google.com/apis/library](https://console.cloud.google.com/apis/library)).
2. Search for each of the following 4 APIs one by one, click on it, and click **ENABLE**:
   - 🔍 Search `Gmail API` -> Click **Enable**
   - 🔍 Search `Google Calendar API` -> Click **Enable**
   - 🔍 Search `Google Drive API` -> Click **Enable**
   - 🔍 Search `Google Tasks API` -> Click **Enable**

### Step 4: Configure OAuth Consent Screen
1. On the left sidebar under **APIs & Services**, click **OAuth consent screen**.
2. Choose **External** user type -> Click **Create**.
3. Fill in the required fields:
   - **App name**: `DeskMate`
   - **User support email**: (Select your email address)
   - **Developer contact information**: (Enter your email address)
4. Click **Save and Continue** (skip Scopes by clicking **Save and Continue** again).
5. On the **Test Users** page, click **+ ADD USERS**, enter your Gmail address, and click **Add**.
6. Click **Save and Continue**.

### Step 5: Download `credentials.json`
1. On the left sidebar under **APIs & Services**, click **Credentials**.
2. Click **+ CREATE CREDENTIALS** at the top bar -> Select **OAuth client ID**.
3. Under **Application type**, choose **Desktop app**.
4. Set Name to `DeskMate Desktop Client`.
5. Click **CREATE**.
6. A popup window will appear showing "OAuth client created". Click **DOWNLOAD JSON**.
7. Go to your Downloads folder and rename the downloaded file to exactly:
   **`credentials.json`**

### Step 6: Place `credentials.json` in App Folder
Move your downloaded **`credentials.json`** file directly into the main application folder next to `DeskMate.exe`:
```
Release/
├── DeskMate.exe
├── credentials.json   <-- Place your file here!
├── flutter_windows.dll
└── data/
```

### Step 7: Launch & Connect
1. Double-click **`DeskMate.exe`**.
2. Select **Personal Agent** in the sidebar toggle.
3. Ask any personal command (e.g. *"Show my calendar for tomorrow"* or *"List my unread emails"*).
4. Your web browser will automatically pop up with the Google authorization page.
5. Click **Continue / Allow**.
6. All 4 checks under **PERSONAL SERVICES HEALTH** (Credentials JSON, Gmail Access, Calendar Access, Drive Access) will turn GREEN! ✅

---

## 💡 Health Dashboard Reference

* **Backend Active**: Green dot indicates local API service is online (`http://127.0.0.1:8080`).
* **Local LLM Active**: Green dot indicates local Ollama / LM Studio server is detected on port `11434` / `1234`.
* **Personal Services Health**: Shows individual green checkmarks for each Google Workspace service once authorized.
