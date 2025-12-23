import { useState, useRef, useCallback, useEffect } from "react"
import {
  useIsEvaluating,
  useConnected,
  useIsConnecting,
  useSubmitOnEnter,
  navigateCommandHistory,
  setSubmitOnEnter,
} from "../stores/konsol-store"
import "@vscode-elements/elements/dist/vscode-checkbox"

type InputProps = {
  onEval: (code: string) => void
}

export function Input({ onEval }: InputProps) {
  const [code, setCode] = useState("")
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const isEvaluating = useIsEvaluating()
  const connected = useConnected()
  const isConnecting = useIsConnecting()
  const submitOnEnter = useSubmitOnEnter()

  const handleSubmit = useCallback(() => {
    const trimmed = code.trim()
    if (!trimmed || isEvaluating || !connected) return
    onEval(trimmed)
    setCode("")
  }, [code, isEvaluating, connected, onEval])

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === "Enter") {
      if (submitOnEnter) {
        // Submit on Enter mode: Enter submits, Alt+Enter for new line
        if (!event.altKey && !event.ctrlKey && !event.metaKey) {
          event.preventDefault()
          handleSubmit()
        }
        // Alt+Enter: allow default behavior (new line)
      } else {
        // Submit on Cmd+Enter mode: Cmd/Ctrl+Enter submits, Enter for new line
        if (event.ctrlKey || event.metaKey) {
          event.preventDefault()
          handleSubmit()
        }
        // Plain Enter: allow default behavior (new line)
      }
    }
    if (event.key === "ArrowUp") {
      event.preventDefault()
      const prev = navigateCommandHistory("up")
      if (prev !== null) setCode(prev)
    }
    if (event.key === "ArrowDown") {
      event.preventDefault()
      const next = navigateCommandHistory("down")
      if (next !== null) setCode(next)
    }
  }

  const handleCheckboxChange = useCallback((event: Event) => {
    const target = event.target as HTMLInputElement
    setSubmitOnEnter(target.checked)
  }, [])

  // Focus textarea when connected
  useEffect(() => {
    if (connected) {
      textareaRef.current?.focus()
    }
  }, [connected])

  const statusText = connected
    ? isEvaluating ? "Evaluating..." : "Connected"
    : isConnecting ? "Connecting..." : "Disconnected"

  const indicatorClass = connected ? "connected" : isConnecting ? "connecting" : ""

  return (
    <div className="konsol-input-container">
      <div className="konsol-input-wrapper">
        <textarea
          ref={textareaRef}
          value={code}
          onChange={(event) => setCode(event.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Enter Ruby code..."
          className="konsol-textarea"
          rows={3}
        />
      </div>
      <div className="konsol-input-footer">
        <div className="konsol-status">
          <div className={`konsol-status-indicator ${indicatorClass}`} />
          <span className="konsol-status-text">{statusText}</span>
        </div>
        <vscode-checkbox
          checked={submitOnEnter || undefined}
          onChange={handleCheckboxChange}
        >
          Submit on Enter
        </vscode-checkbox>
      </div>
    </div>
  )
}
