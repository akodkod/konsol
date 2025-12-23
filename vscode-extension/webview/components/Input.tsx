import { useState, useRef, useCallback, useEffect } from "react"
import { useIsEvaluating, useConnected, navigateCommandHistory } from "../stores/konsol-store"
import "@vscode-elements/elements/dist/vscode-button"

type InputProps = {
  onEval: (code: string) => void
}

export function Input({ onEval }: InputProps) {
  const [code, setCode] = useState("")
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const isEvaluating = useIsEvaluating()
  const connected = useConnected()

  const handleSubmit = useCallback(() => {
    const trimmed = code.trim()
    if (!trimmed || isEvaluating || !connected) return
    onEval(trimmed)
    setCode("")
  }, [code, isEvaluating, connected, onEval])

  const handleKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      handleSubmit()
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

  // Focus textarea when connected
  useEffect(() => {
    if (connected) {
      textareaRef.current?.focus()
    }
  }, [connected])

  const isDisabled = !code.trim() || isEvaluating || !connected

  return (
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
      <vscode-button
        appearance="primary"
        disabled={isDisabled || undefined}
        onClick={handleSubmit}
      >
        {isEvaluating ? "Running..." : "Run"}
      </vscode-button>
    </div>
  )
}
