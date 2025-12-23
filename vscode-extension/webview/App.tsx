import { useEffect } from "react"
import { match } from "ts-pattern"
import { Output } from "./components/Output"
import { Input } from "./components/Input"
import {
  connect,
  disconnect,
  addCommand,
  addEvalResult,
  addOutput,
  clearOutput,
  startEvaluating,
  finishEvaluating,
  restorePersistedState,
} from "./stores/konsol-store"
import { vscode } from "./lib/vscode-api"
import { parseExtensionToWebview } from "../shared/schemas"
import type { ExtensionToWebview, StdoutParams, StderrParams, StatusParams } from "../shared/types"

export function App() {
  useEffect(() => {
    // Restore persisted preferences from VSCode state
    restorePersistedState()

    const handleMessage = (event: MessageEvent<ExtensionToWebview>) => {
      const parsed = parseExtensionToWebview(event.data)
      if (!parsed.success) {
        console.error("Invalid message from extension:", parsed.error)
        return
      }

      match(parsed.data)
        .with({ type: "connected" }, ({ sessionId }) => {
          connect(sessionId)
        })
        .with({ type: "disconnected" }, () => {
          disconnect()
        })
        .with({ type: "result" }, ({ data }) => {
          finishEvaluating()
          addEvalResult(data)
        })
        .with({ type: "error" }, ({ message }) => {
          finishEvaluating()
          addOutput("error", `Error: ${message}`)
        })
        .with({ type: "notification" }, ({ method, params }) => {
          if (method === "konsol/stdout") {
            const typedParams = params as StdoutParams
            if (typedParams.chunk) {
              addOutput("stdout", typedParams.chunk)
            }
          } else if (method === "konsol/stderr") {
            const typedParams = params as StderrParams
            if (typedParams.chunk) {
              addOutput("stderr", typedParams.chunk)
            }
          } else if (method === "konsol/status") {
            const typedParams = params as StatusParams
            if (typedParams.busy) {
              startEvaluating()
            } else {
              finishEvaluating()
            }
          }
        })
        .with({ type: "clear" }, () => {
          clearOutput()
        })
        .exhaustive()
    }

    window.addEventListener("message", handleMessage)
    vscode.postMessage({ type: "ready" })

    return () => window.removeEventListener("message", handleMessage)
  }, [])

  const handleEval = (code: string) => {
    const trimmed = code.trim().toLowerCase()
    if (trimmed === "exit" || trimmed === "quit") {
      addCommand(code)
      vscode.postMessage({ type: "disconnect" })
      return
    }
    addCommand(code)
    startEvaluating()
    vscode.postMessage({ type: "eval", code })
  }

  return (
    <div className="konsol-container">
      <Output />
      <Input onEval={handleEval} />
    </div>
  )
}
