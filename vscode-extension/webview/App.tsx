import { useEffect } from "react"
import { match } from "ts-pattern"
import { Output } from "./components/Output"
import { Input } from "./components/Input"
import { StatusBar } from "./components/StatusBar"
import {
  setConnected,
  addCommand,
  addEvalResult,
  addOutput,
  clearOutput,
  setEvaluating,
} from "./stores/konsol-store"
import { vscode } from "./lib/vscode-api"
import { parseExtensionToWebview } from "../shared/schemas"
import type { ExtensionToWebview, StdoutParams, StderrParams, StatusParams } from "../shared/types"

export function App() {
  useEffect(() => {
    const handleMessage = (event: MessageEvent<ExtensionToWebview>) => {
      const parsed = parseExtensionToWebview(event.data)
      if (!parsed.success) {
        console.error("Invalid message from extension:", parsed.error)
        return
      }

      match(parsed.data)
        .with({ type: "connected" }, ({ sessionId }) => {
          setConnected(true, sessionId)
        })
        .with({ type: "disconnected" }, () => {
          setConnected(false)
        })
        .with({ type: "result" }, ({ data }) => {
          setEvaluating(false)
          addEvalResult(data)
        })
        .with({ type: "error" }, ({ message }) => {
          setEvaluating(false)
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
            setEvaluating(typedParams.busy)
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
    addCommand(code)
    setEvaluating(true)
    vscode.postMessage({ type: "eval", code })
  }

  return (
    <div className="konsol-container">
      <Output />
      <StatusBar />
      <Input onEval={handleEval} />
    </div>
  )
}
