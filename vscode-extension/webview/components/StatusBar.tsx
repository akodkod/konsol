import { useConnected, useSessionId, useIsEvaluating } from "../stores/konsol-store"

export function StatusBar() {
  const connected = useConnected()
  const sessionId = useSessionId()
  const isEvaluating = useIsEvaluating()

  let statusText = "Disconnected"
  if (connected && sessionId) {
    const shortId = sessionId.substring(0, 8)
    statusText = isEvaluating
      ? `Evaluating... (session: ${shortId}...)`
      : `Connected (session: ${shortId}...)`
  }

  return (
    <div className="konsol-status-bar">
      <div className={`konsol-status-indicator ${connected ? "connected" : ""}`} />
      <span className="konsol-status-text">{statusText}</span>
    </div>
  )
}
