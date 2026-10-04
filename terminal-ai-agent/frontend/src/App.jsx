import { useEffect, useMemo, useRef, useState } from 'react'

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL?.trim() || 'http://localhost:8000'
const STORAGE_API_KEY = 'deskmate_gemini_api_key'
const STORAGE_CONVERSATION_ID = 'deskmate_conversation_id'

const generateId = () => Date.now().toString(36) + Math.random().toString(36).substring(2)

const starterMessages = [
  {
    id: 'welcome',
    role: 'assistant',
    content: 'Enter your API key, then start chatting.',
  },
]

const quickPrompts = [
  'Summarize the current folder structure.',
  'Help me inspect the backend files.',
  'Show me a clean chat layout idea for this app.',
]

function MessageBubble({ role, content }) {
  return (
    <article className={`bubble bubble-${role}`}>
      <div className="bubble-label">{role === 'user' ? 'You' : 'Assistant'}</div>
      <p>{content}</p>
    </article>
  )
}

function App() {
  const [apiKeyDraft, setApiKeyDraft] = useState('')
  const [apiKey, setApiKey] = useState('')
  const [conversationId, setConversationId] = useState(() =>
    localStorage.getItem(STORAGE_CONVERSATION_ID) || ''
  )

  const [messages, setMessages] = useState(starterMessages)
  const [message, setMessage] = useState('')
  const [isSending, setIsSending] = useState(false)
  const [error, setError] = useState('')
  const [isSettingsOpen, setIsSettingsOpen] = useState(false)
  const endRef = useRef(null)

  const hasApiKey = Boolean(apiKey.trim())

  const readinessText = useMemo(() => {
    if (!hasApiKey) return 'Configure API key in Settings'
    return conversationId ? 'Session active' : 'Ready'
  }, [hasApiKey, conversationId])

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, isSending])

  const saveApiKey = () => {
    const key = apiKeyDraft.trim()
    if (!key) {
      setError('Please enter an API key.')
      return
    }

    setApiKey(key)
    setError('')

    if (messages.length === 1 && messages[0].id === 'welcome') {
      setMessages([
        {
          id: generateId(),
          role: 'assistant',
          content: 'API key loaded. You can start chatting now.',
        },
      ])
    }
  }

  const resetChat = async () => {
    const prev = conversationId

    setMessages(starterMessages)
    setConversationId('')
    localStorage.removeItem(STORAGE_CONVERSATION_ID)

    if (!prev) return

    try {
      await fetch(`${BACKEND_URL}/api/reset/${prev}`, { method: 'POST' })
    } catch {}
  }

  const sendMessage = async (e) => {
    e.preventDefault()

    const trimmed = message.trim()
    if (!trimmed || isSending) return

    if (!hasApiKey) {
      setError('API key required. Open Settings to set your Gemini API key.')
      return
    }

    const userMsg = {
      id: generateId(),
      role: 'user',
      content: trimmed,
    }

    setMessages((prev) => [...prev, userMsg])
    setMessage('')
    setIsSending(true)
    setError('')

    try {
      const res = await fetch(`${BACKEND_URL}/api/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          api_key: apiKey,
          conversation_id: conversationId || undefined,
          message: trimmed,
        }),
      })

      const data = await res.json()

      if (!res.ok) throw new Error(data?.detail || 'Request failed')

      setConversationId(data.conversation_id)
      localStorage.setItem(STORAGE_CONVERSATION_ID, data.conversation_id)

      setMessages((prev) => [
        ...prev,
        {
          id: generateId(),
          role: 'assistant',
          content: data.reply,
        },
      ])
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Unknown error'
      setError(msg)

      setMessages((prev) => [
        ...prev,
        {
          id: generateId(),
          role: 'assistant',
          content: `Error: ${msg}`,
        },
      ])
    } finally {
      setIsSending(false)
    }
  }

  return (
    <div className="app-shell">
      <div className="grid-overlay" />

      <main className="layout">

        {/* SIDEBAR */}
        <aside className="panel sidebar">
          
          {/* BRAND */}
          <div className="brand-block">
            <span className="eyebrow">DeskMate</span>
            <h1>DeskMate</h1>
            <p className="helper-text">Open Source AI</p>
          </div>

          {/* STATUS */}
          <div className="status-card">
            <span className="status-dot" />
            <div>
              <p className="status-title">Status</p>
              <p className="status-copy">{readinessText}</p>
            </div>
          </div>

          {/* QUICK PROMPTS */}
          <div className="info-card">
            <p className="info-title">Quick prompts</p>
            <div className="prompt-list">
              {quickPrompts.map((p) => (
                <button
                  key={p}
                  type="button"
                  className="prompt-chip"
                  onClick={() => setMessage(p)}
                >
                  {p}
                </button>
              ))}
            </div>
          </div>

          <div style={{ marginTop: 'auto' }}>
            <button
              className="ghost-button"
              style={{ width: '100%' }}
              onClick={() => setIsSettingsOpen(true)}
              type="button"
            >
              ⚙ Settings
            </button>
          </div>
        </aside>

        {/* CHAT */}
        <section className="panel chat-panel">

          <div className="chat-header">
            <div>
              <h2>DeskMate Workspace</h2>
              <p className="helper-text">File Explorer & Personal Assistant</p>
            </div>
            <button className="ghost-button" onClick={resetChat} type="button">
              New Chat
            </button>
          </div>

          <div className="message-stream">
            {messages.map((m) => (
              <MessageBubble key={m.id} role={m.role} content={m.content} />
            ))}

            {isSending && (
              <article className="bubble bubble-assistant bubble-typing">
                <div className="bubble-label">Assistant</div>
                <div className="typing-indicator">
                  <span />
                  <span />
                  <span />
                </div>
              </article>
            )}

            <div ref={endRef} />
          </div>

          {/* COMPOSER */}
          <form className="composer" onSubmit={sendMessage}>
            <textarea
              className="composer-input"
              rows="3"
              placeholder={hasApiKey ? 'Type a message...' : 'Configure Gemini API Key in Settings to start chatting'}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault()
                  sendMessage(e)
                }
              }}
            />

            <div className="composer-footer">
              <p className="helper-text">
                Enter to send • Shift + Enter for new line
              </p>

              <button
                type="submit"
                className="primary-button"
                disabled={!message.trim() || isSending || !hasApiKey}
              >
                {isSending ? 'Sending...' : 'Send'}
              </button>
            </div>

            {error && <p className="error-text">{error}</p>}
          </form>

        </section>
      </main>

      {/* SETTINGS DRAWER OVERLAY */}
      {isSettingsOpen && (
        <div
          style={{
            position: 'fixed',
            inset: 0,
            zIndex: 1000,
            background: 'rgba(1, 4, 9, 0.45)',
            display: 'flex',
            justifyContent: 'flex-end',
          }}
          onClick={() => setIsSettingsOpen(false)}
        >
          <div
            style={{
              width: 420,
              height: '100%',
              background: '#161b22',
              borderLeft: '1px solid #30363d',
              padding: 24,
              display: 'flex',
              flexDirection: 'column',
              gap: 20,
              boxShadow: '0 0 30px rgba(1, 4, 9, 0.5)',
            }}
            onClick={(e) => e.stopPropagation()}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <h3 style={{ margin: 0, fontSize: '1.25rem', color: '#e6edf3' }}>Settings</h3>
                <p style={{ margin: '4px 0 0', fontSize: '0.8rem', color: '#8b949e' }}>
                  Manage your DeskMate preferences
                </p>
              </div>
              <button
                className="ghost-button"
                style={{ padding: '6px 12px' }}
                onClick={() => setIsSettingsOpen(false)}
              >
                ✕
              </button>
            </div>

            <hr style={{ borderColor: '#30363d', margin: 0 }} />

            {/* AI CONFIGURATION */}
            <div>
              <h4 style={{ margin: '0 0 4px', color: '#e6edf3' }}>AI Configuration</h4>
              <p style={{ margin: '0 0 12px', fontSize: '0.8rem', color: '#8b949e' }}>
                Configure your AI provider.
              </p>
              <label className="field-label">Gemini API Key</label>
              <input
                className="text-input"
                type="password"
                placeholder="Enter Gemini API key"
                value={apiKeyDraft}
                onChange={(e) => setApiKeyDraft(e.target.value)}
                style={{ marginTop: 6 }}
              />
              <button
                className="primary-button"
                onClick={() => {
                  saveApiKey()
                  setIsSettingsOpen(false)
                }}
                type="button"
                style={{ width: '100%', marginTop: 12 }}
              >
                Load Gemini API
              </button>
            </div>

          </div>
        </div>
      )}
    </div>
  )
}

export default App