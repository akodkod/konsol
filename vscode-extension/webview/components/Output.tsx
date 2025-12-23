import { useEffect, useRef, useCallback } from "react"
import { useOutput, useConnected, useIsConnecting, startConnecting } from "../stores/konsol-store"
import { parseAnsi } from "../lib/ansi"
import { vscode } from "../lib/vscode-api"
import "@vscode-elements/elements/dist/vscode-button"

export function Output() {
  const output = useOutput()
  const connected = useConnected()
  const isConnecting = useIsConnecting()
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [output])

  const handleConnect = useCallback(() => {
    startConnecting()
    vscode.postMessage({ type: "connect" })
  }, [])

  const getClassName = (type: string) => {
    const classMap: Record<string, string> = {
      prompt: "konsol-prompt",
      result: "konsol-result",
      error: "konsol-error",
      stdout: "konsol-stdout",
      stderr: "konsol-stderr",
    }
    return `konsol-output-line ${classMap[type] || ""}`
  }

  if (output.length === 0) {
    return (
      <div className="konsol-output">
        <div className="konsol-welcome">
          <h3>Konsol - Rails Console</h3>
          {connected ? (
            <p>Press <code>Enter</code> to run, <code>↑/↓</code> for history</p>
          ) : (
            <vscode-button
              appearance="primary"
              icon={isConnecting ? "loading~spin" : "plug"}
              disabled={isConnecting}
              onClick={handleConnect}
            >
              {isConnecting ? "Connecting..." : "Connect"}
            </vscode-button>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className="konsol-output">
      {output.map((entry) => (
        <div key={entry.id} className={getClassName(entry.type)}>
          {parseAnsi(entry.content)}
        </div>
      ))}
      <div ref={bottomRef} />
    </div>
  )
}
