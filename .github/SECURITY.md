# Security Policy

DeskMate is built with a **privacy-first, local-first architecture**. All files, documents, audio recordings, SQLite databases, and Ollama reasoning models remain strictly on your local machine by design.

We take the security and privacy of our users and contributors seriously.

---

## Supported Versions

Only the latest continuous pre-release and the most recent stable release receive active security updates.

| Version | Supported          |
| ------- | ------------------ |
| `main` (Latest) | :white_check_mark: |
| `v1.0.x` | :white_check_mark: |
| `< 1.0.0` | :x: |

---

## Reporting a Vulnerability

If you discover a security vulnerability or privacy flaw in DeskMate, please do **NOT** open a public issue. Publicly disclosing a vulnerability can put the community at risk.

### Preferred Reporting Method

1. **GitHub Private Vulnerability Reporting**:
   - Navigate to the **Security** tab of this repository.
   - Click on **Advisories** and then **Report a vulnerability**.
   - Fill out the advisory form with detailed reproduction steps.

2. **Email Disclosure**:
   - Alternatively, you can email the maintainer directly at:  
     **`ganeshvenkatesanofficial@gmail.com`**
   - Please include:
     - A description of the issue and potential security impact
     - Clear step-by-step instructions or proof-of-concept (PoC) to reproduce
     - Your OS version (macOS / Windows) and architecture

### Response Timeline

- **Initial Acknowledgement**: Within **48 hours**.
- **Assessment & Confirmation**: Within **5 business days**.
- **Fix & Advisory Release**: Coordinated with the reporter before public disclosure.

---

## Core Security & Privacy Principles

DeskMate adheres to the following privacy-by-design standards:

1. **Local-Only Processing**:
   - Local AI models run entirely on `http://127.0.0.1:11434` via Ollama without cloud telemetry.
   - Embeddings and vector searches (Qdrant) operate locally on disk (`.qdrant_data`).
2. **BYOK (Bring-Your-Own-Key)**:
   - Google Gemini API keys and OAuth credentials are saved exclusively to your local device.
   - Keys are never logged, tracked, or relayed to third-party analytics servers.
3. **Local Artifacts**:
   - Transcripts, screenshots, and PDF session reports remain strictly inside your local DeskMate application storage.
