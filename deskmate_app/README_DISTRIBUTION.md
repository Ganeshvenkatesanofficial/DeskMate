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

To enable **Gmail, Calendar, Drive & Tasks** integrations and get all **PERSONAL AGENT HEALTH** checkmarks green, follow these exact steps in Google Cloud Console:

---

### Step 1: Open Google Cloud Console & Create Project
1. Open your browser and go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Sign in with your Google account.
3. At the top navigation bar (next to the Google Cloud logo), click the **Project Dropdown**.
4. Click **New Project** in the top-right of the modal window.
5. Enter a Project Name (e.g. `DeskMate`) and click **Create**.
6. Wait 5–10 seconds, then select your new project from the top dropdown or the notification bell.

---

### Step 2: Enable the 4 Required APIs
You must enable 4 Google Workspace APIs for DeskMate to read/write emails, calendar events, documents, and tasks:

1. In the left navigation, click **APIs & Services** ➔ **Library** (or visit [https://console.cloud.google.com/apis/library](https://console.cloud.google.com/apis/library)).
2. Search for and enable each of the following 4 APIs one by one:
   - 🔍 Search `Gmail API` ➔ Click on it ➔ Click **Enable**
   - 🔍 Search `Google Calendar API` ➔ Click on it ➔ Click **Enable**
   - 🔍 Search `Google Drive API` ➔ Click on it ➔ Click **Enable**
   - 🔍 Search `Google Tasks API` ➔ Click on it ➔ Click **Enable**

> [!NOTE]
> **Why are all methods automatically selected?**
> When you click **Enable**, Google redirects you to the **API/Service details** page showing `Status: Enabled` and a filter like `Methods: 17 options selected`.
> **You do NOT need to uncheck or configure any methods.** Google Cloud automatically selects and enables all API methods by default. Leave this as-is!
> You will also see a top banner: *"To call this API from your own applications, you may need to create credentials"*. You can now proceed to set up branding and credentials.

---

### Step 3: Configure Google Auth Platform / Branding (OAuth Consent Screen)
Google requires your application to have an OAuth branding profile before generating client keys.

1. In the left sidebar, click **Google Auth Platform** ➔ **Overview** (or **APIs & Services** ➔ **OAuth consent screen**).
2. Click **Create branding** (or **Get Started** / **Configure**).
3. Complete the 4-step setup wizard:
   - **1. App Information**:
     - **App name**: Enter `DeskMate` *(Mandatory: Leaving this blank causes an error "Application name must not be empty")*.
     - **User support email**: Click the dropdown menu and select your personal Gmail address (e.g. `yourname@gmail.com`).
     - Click the blue **Next** button.
   - **2. Audience (What is Audience?)**:
     - **What is Audience?**: Google uses this setting to determine which users are authorized to sign in to your app.
     - **Internal**: Restricted exclusively to users within your organization's Google Workspace domain. *(Unavailable for standard `@gmail.com` accounts)*.
     - **External**: Allows any standard Google account user (`@gmail.com` or custom domains) to log in.
     - **Action**: Select **External**, then click the blue **Next** button.
   - **3. Contact Information**:
     - **Developer contact information**: Enter your email address (`yourname@gmail.com`) so Google can send developer alerts.
     - Click the blue **Next** button.
   - **4. Finish**:
     - Check the box: `☑ I agree to the Google API services user data policy`.
     - Click the blue **Continue** button.
     - Click the blue **Create** button at the bottom of the page to finalize your branding.

---

### Step 4: CRITICAL: Add Your Email as a Test User
> [!IMPORTANT]
> **Why is adding a Test User required?**
> Newly created Google Cloud apps have a publishing status of **"Testing"** (unverified by Google).
> While in "Testing" mode, Google's security blocks any login attempt with:
> `Error 403: access_denied — DeskMate has not completed the Google verification process`.
> **Only Google accounts explicitly added to your Test Users list are permitted to log in!**

1. On the left sidebar under **Google Auth Platform** (or **OAuth consent screen**), click **Audience** (or the **Test users** tab).
2. Scroll to the **Test users** section.
3. Click the **+ ADD USERS** button.
4. Type in your personal Google email address (`yourname@gmail.com`) — this must be the exact account you will log into DeskMate with.
5. Click **Save** / **Add**.

---

### Step 5: Create Desktop OAuth 2.0 Client ID
Now generate the client credentials for the DeskMate desktop app:

1. On the left sidebar, click **Clients** (or **APIs & Services** ➔ **Credentials** ➔ **+ CREATE CREDENTIALS** ➔ **OAuth client ID**).
2. Set the configuration:
   - **Application type**: Select **Desktop app** from the dropdown.
     *(CRITICAL: Do NOT select "Web application", "Android", or "iOS". DeskMate is a local desktop application and uses loopback redirect ports provided by Desktop app).*
   - **Name**: Enter `DeskMate Desktop Client` (or leave default `Desktop client 1`).
   - *(Optional)* "Use this client for an AI-powered agent": Leave unchecked or optional.
3. Click the blue **Create** button.
4. A popup modal titled **OAuth client created** will appear with:
   - Notice: *"OAuth access is restricted to the test users listed on your OAuth consent screen."*
   - Warning: *"You will no longer be able to view or download the client secret once you close this dialogue."*
   - **Client ID** (format: `1000888210114-...apps.googleusercontent.com`) with a copy button.
   - **Client secret** (format: `GOCSPX-...`) with a copy button.
   - A **Download JSON** button.

---

### Step 6: Connect Credentials to DeskMate (Two Easy Ways)

You can choose either of the following two methods:

#### Method A: Direct In-App Setup (Fastest — No File Moving)
1. In the Google Cloud modal, click the copy icon next to **Client ID**.
2. Open DeskMate ➔ Click **Credentials Setup** in the sidebar (or ⚙️ Settings).
3. Paste into the **Client ID** field.
4. In the Google Cloud modal, click the copy icon next to **Client secret**.
5. Paste into the **Client Secret** field in DeskMate.
6. Click **Save Credentials**. DeskMate stores them securely in local configuration!

#### Method B: Download `credentials.json` File
1. In the Google Cloud modal, click **Download JSON**.
2. Find the downloaded file (e.g. `client_secret_....json`) in your Downloads folder.
3. Rename the file to exactly:
   **`credentials.json`**
4. Move `credentials.json` directly into the DeskMate app folder:
   - **Windows**: Place it next to `DeskMate.exe`:
     ```text
     Release/
     ├── DeskMate.exe
     ├── credentials.json   <-- Place here!
     ├── flutter_windows.dll
     └── data/
     ```
   - **macOS**: Place it in `~/Library/Application Support/DeskMate/credentials.json` or next to the DeskMate app bundle.

---

### Step 7: Launch & One-Click Authorization
1. Open DeskMate.
2. Select **Personal Agent** in the sidebar mode selector.
3. Ask any command in chat:
   - *"Show my calendar for tomorrow"*
   - *"List my unread emails"*
   - *"Show my to-do tasks"*
4. Your default web browser will automatically open Google's authorization screen.
5. Sign in using the same email you added as a **Test User** in Step 4.
6. Click **Continue** (if prompted that the app is unverified) and click **Allow** to grant permissions.
7. Return to DeskMate: All indicators under **PERSONAL AGENT HEALTH** will turn GREEN! ✅

---

## 💡 Health Dashboard Reference

* **Backend Active**: Green dot indicates local API service is online (`http://127.0.0.1:8080`).
* **Local LLM Active**: Green dot indicates local Ollama / LM Studio server is detected on port `11434` / `1234`.
* **Personal Services Health**: Shows individual green checkmarks for each Google Workspace service once authorized.

---

## ✉️ Meeting Scribe Email Dispatch & Screenshot Filtering

* **Dynamic Synthesis**: Executive summaries, key decisions, and action items are synthesized in real-time from active screens and Voxtral 4B diarized transcripts (zero mock or placeholder text).
* **Sender Attribution & Designation**: Emails are sent directly from your connected Gmail with your verified Name, Designation / Role, and contact email in the header banner and signature card.
* **DeskMate App Screenshot Redaction**: Internal DeskMate host application windows and UI dialogs are automatically filtered out, ensuring visual audit cards and PDF attachments only feature external presentations, code, slides, and shared windows.
* **Properly-Named PDF Attachment**: Attached PDF reports are formatted professionally (e.g., `DeskMate_Executive_Meeting_Report_YYYY-MM-DD.pdf`).
* **Creator & Open-Source Branding**: Emails feature DeskMate AI branding, Ganesh Venkatesan creator attribution, and LinkedIn profile verification (`https://www.linkedin.com/in/ganesh-venkatesan-3a4516256/`).

---

## 👁️ Visual Intelligence & Model Requirements

### 1. Where Does NVIDIA LocateAnything-3B Work?
* **Live Recording Grounding**: Operates **during the live meeting session**. Whenever a click or UI event occurs, `LocateAnythingDetector` (Parallel Box Decoding) localizes the exact button, dialog, slide region, or code element clicked into spatial bounding boxes and records them in the event narrative.

### 2. Visual Intelligence: 3 Flexible Options
DeskMate provides 3 flexible ways to process meetings, making it extremely feasible for both high-end workstations and small laptops:
* **Option A: 💻 Lightweight Laptop Mode (Small Laptops / 8GB–16GB RAM)**:
  * **Zero heavy downloads**: Users on compact ultrabooks or low-spec laptops do not need to pull multi-gigabyte vision weights.
  * DeskMate combines high-precision screen OCR + NVIDIA bounding box coordinates with your **active local reasoning model** (e.g. `qwen2.5-coder:1.5b` or `gpt-oss:20b`) and Voxtral speech diarization.
  * **1-Click Activation**: Click the Vision status indicator in the Meeting sidebar or modal to toggle Lightweight Laptop Mode instantly.
* **Option B: 🦙 Full Multimodal Vision (`llama3.2-vision`)**:
  * For 16GB+ RAM laptops. Pull via `ollama run llama3.2-vision` to inspect raw screenshots pixel-by-pixel.
* **Option C: ☁️ Google Gemini Cloud Vision**:
  * When a **Google Gemini API Key** is configured in Settings, cloud multimodal reasoning is used natively. **Zero local RAM needed**, and no local vision model download is required.

### 3. Agentic Post-Recording Telemetry Flow
When you click **"End Meeting"**, DeskMate replaces the opaque loading spinner with an animated **Live Agentic Mission Control Stepper**:
1. **Audio Prep**: Buffer flush and conversion to 16kHz mono PCM WAV.
2. **Voxtral 4B Diarization**: In-memory speaker clustering and timestamped conversational turns.
3. **Multimodal Synthesis**: Cross-referencing visual OCR and dialogue via your active model.
4. **PDF Compilation**: Generating vector PDF reports with redacted host UI and syncing action items.
* Features a live elapsed stopwatch timer (`00:08s`) and streaming console feed.
