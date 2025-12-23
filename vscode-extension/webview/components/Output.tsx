import { useEffect, useRef } from "react"
import { useOutput } from "../stores/konsol-store"

export function Output() {
  const output = useOutput()
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [output])

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
          <p>Press <code>Ctrl/Cmd+Enter</code> to run, <code>↑/↓</code> for history</p>
        </div>
      </div>
    )
  }

  return (
    <div className="konsol-output">
      {output.map((entry) => (
        <div key={entry.id} className={getClassName(entry.type)}>
          {entry.content}
        </div>
      ))}
      <div ref={bottomRef} />
    </div>
  )
}
