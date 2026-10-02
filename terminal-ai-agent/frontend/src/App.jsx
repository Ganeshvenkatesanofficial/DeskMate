import { useEffect, useMemo, useRef, useState } from 'react'

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL?.trim() || 'http://localhost:8000'
const STORAGE_API_KEY = 'filelens_gemini_api_key'
const STORAGE_CONVERSATION_ID = 'filelens_conversation_id'

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
  const endRef = useRef(null)

  const hasApiKey = Boolean(apiKey.trim())

  const readinessText = useMemo(() => {
    if (!hasApiKey) return 'Waiting for API key.'
    return conversationId ? 'Session active.' : 'Ready.'
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
      setError('API key required.')
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
      <div className="glow glow-a" />
      <div className="glow glow-b" />
      <div className="grid-overlay" />

      <main className="layout">

        {/* SIDEBAR */}
        <aside className="panel sidebar">
          
          {/* BRAND */}
          <div className="brand-block">
            <span className="eyebrow">FILELEN</span>
            <h1>FILELEN</h1>
          </div>

          {/* STATUS */}
          <div className="status-card">
            <span className="status-dot" />
            <div>
              <p className="status-title">Status</p>
              <p className="status-copy">{readinessText}</p>
            </div>
          </div>

          {/* API KEY */}
          <label className="field-label">API Key</label>
          <input
            className="text-input"
            type="password"
            placeholder="Enter API key"
            value={apiKeyDraft}
            onChange={(e) => setApiKeyDraft(e.target.value)}
          />

          <div className="sidebar-actions">
            <button className="primary-button" onClick={saveApiKey} type="button">
              Load Key
            </button>
            <button className="ghost-button" onClick={resetChat} type="button">
              New Chat
            </button>
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
        </aside>

        {/* CHAT */}
        <section className="panel chat-panel">

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
              placeholder={hasApiKey ? 'Type a message...' : 'Enter API key first'}
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
    </div>
  )
}

export default App