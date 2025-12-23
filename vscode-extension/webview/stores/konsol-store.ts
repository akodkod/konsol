import { create } from "zustand"
import type { EvalResult, OutputEntry, OutputEntryType } from "../../shared/types"
import { vscode } from "../lib/vscode-api"

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export enum KonsolStatus {
  Disconnected = "disconnected",
  Connecting = "connecting",
  Connected = "connected",
  Evaluating = "evaluating",
}

type KonsolState = {
  status: KonsolStatus
  sessionId: string | null
  output: OutputEntry[]
  commandHistory: string[]
  commandHistoryIndex: number
  submitOnEnter: boolean
}

// ─────────────────────────────────────────────────────────────────────────────
// Store (private — NOT exported)
// ─────────────────────────────────────────────────────────────────────────────

const store = create<KonsolState>()(() => ({
  status: KonsolStatus.Disconnected,
  sessionId: null,
  output: [],
  commandHistory: [],
  commandHistoryIndex: -1,
  submitOnEnter: true,
}))

// ─────────────────────────────────────────────────────────────────────────────
// Selectors (exported hooks)
// ─────────────────────────────────────────────────────────────────────────────

export const useStatus = () => store((state) => state.status)
export const useConnected = () =>
  store((state) => state.status === KonsolStatus.Connected || state.status === KonsolStatus.Evaluating)
export const useIsConnecting = () => store((state) => state.status === KonsolStatus.Connecting)
export const useIsEvaluating = () => store((state) => state.status === KonsolStatus.Evaluating)
export const useSessionId = () => store((state) => state.sessionId)
export const useOutput = () => store((state) => state.output)
export const useCommandHistory = () => store((state) => state.commandHistory)
export const useCommandHistoryIndex = () => store((state) => state.commandHistoryIndex)
export const useSubmitOnEnter = () => store((state) => state.submitOnEnter)

// ─────────────────────────────────────────────────────────────────────────────
// Mutators (exported actions)
// ─────────────────────────────────────────────────────────────────────────────

export const startConnecting = () => {
  store.setState({ status: KonsolStatus.Connecting })
}

export const connect = (sessionId: string) => {
  store.setState({ status: KonsolStatus.Connected, sessionId })
}

export const disconnect = () => {
  store.setState({ status: KonsolStatus.Disconnected, sessionId: null })
}

export const addOutput = (type: OutputEntryType, content: string) => {
  const entry: OutputEntry = {
    id: crypto.randomUUID(),
    type,
    content,
    timestamp: new Date(),
  }
  store.setState((state) => ({ output: [...state.output, entry] }))
}

export const addEvalResult = (result: EvalResult) => {
  if (result.stdout) {
    addOutput("stdout", result.stdout)
  }
  if (result.stderr) {
    addOutput("stderr", result.stderr)
  }
  if (result.exception) {
    addOutput("error", `${result.exception.class}: ${result.exception.message}`)
    result.exception.backtrace.slice(0, 5).forEach((line) => {
      addOutput("error", `  ${line}`)
    })
  } else {
    const display = result.valueType
      ? `=> ${result.value} (${result.valueType})`
      : `=> ${result.value}`
    addOutput("result", display)
  }
}

export const addCommand = (code: string) => {
  addOutput("prompt", `> ${code}`)
  store.setState((state) => ({
    commandHistory: [...state.commandHistory, code],
    commandHistoryIndex: -1,
  }))
}

export const clearOutput = () => {
  store.setState({ output: [], commandHistoryIndex: -1 })
}

export const startEvaluating = () => {
  store.setState({ status: KonsolStatus.Evaluating })
}

export const finishEvaluating = () => {
  store.setState({ status: KonsolStatus.Connected })
}

export const setSubmitOnEnter = (submitOnEnter: boolean) => {
  store.setState({ submitOnEnter })
  // Persist to VSCode state
  const currentState = vscode.getState() as Record<string, unknown> | undefined
  vscode.setState({ ...currentState, submitOnEnter })
}

export const restorePersistedState = () => {
  const state = vscode.getState() as { submitOnEnter?: boolean } | undefined
  if (state?.submitOnEnter !== undefined) {
    store.setState({ submitOnEnter: state.submitOnEnter })
  }
}

export const navigateCommandHistory = (direction: "up" | "down"): string | null => {
  const { commandHistory, commandHistoryIndex } = store.getState()
  if (commandHistory.length === 0) return null

  let newIndex: number
  if (direction === "up") {
    newIndex = commandHistoryIndex === -1
      ? commandHistory.length - 1
      : Math.max(0, commandHistoryIndex - 1)
  } else {
    newIndex = commandHistoryIndex === -1
      ? -1
      : Math.min(commandHistory.length - 1, commandHistoryIndex + 1)
  }

  store.setState({ commandHistoryIndex: newIndex })
  return newIndex >= 0 ? commandHistory[newIndex] : null
}
