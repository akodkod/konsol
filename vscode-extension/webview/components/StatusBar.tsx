import { useStatus, useSessionId, KonsolStatus } from "../stores/konsol-store"

export function StatusBar() {
  const status = useStatus()
  const sessionId = useSessionId()

  const isConnecting = status === KonsolStatus.Connecting
  const isConnected = status === KonsolStatus.Connected || status === KonsolStatus.Evaluating
  const shortId = sessionId?.substring(0, 8)

  const statusText = {
    [KonsolStatus.Disconnected]: "Disconnected",
    [KonsolStatus.Connecting]: "Connecting...",
    [KonsolStatus.Connected]: `Connected (session: ${shortId}...)`,
    [KonsolStatus.Evaluating]: `Evaluating... (session: ${shortId}...)`,
  }[status]

  const indicatorClass = isConnected ? "connected" : isConnecting ? "connecting" : ""

  return (
    <div className="konsol-status-bar">
      <div className={`konsol-status-indicator ${indicatorClass}`} />
      <span className="konsol-status-text">{statusText}</span>
    </div>
  )
}
