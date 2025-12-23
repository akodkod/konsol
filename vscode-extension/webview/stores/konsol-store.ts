import { create } from "zustand"
import type { EvalResult, OutputEntry, OutputEntryType } from "../../shared/types"

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

type KonsolState = {
  connected: boolean
  sessionId: string | null
  output: OutputEntry[]
  commandHistory: string[]
  commandHistoryIndex: number
  isEvaluating: boolean
}

// ─────────────────────────────────────────────────────────────────────────────
// Store (private — NOT exported)
// ─────────────────────────────────────────────────────────────────────────────

const store = create<KonsolState>()(() => ({
  connected: false,
  sessionId: null,
  output: [],
  commandHistory: [],
  commandHistoryIndex: -1,
  isEvaluating: false,
}))

// ─────────────────────────────────────────────────────────────────────────────
// Selectors (exported hooks)
// ─────────────────────────────────────────────────────────────────────────────

export const useConnected = () => store((state) => state.connected)
export const useSessionId = () => store((state) => state.sessionId)
export const useOutput = () => store((state) => state.output)
export const useCommandHistory = () => store((state) => state.commandHistory)
export const useCommandHistoryIndex = () => store((state) => state.commandHistoryIndex)
export const useIsEvaluating = () => store((state) => state.isEvaluating)

// ─────────────────────────────────────────────────────────────────────────────
// Mutators (exported actions)
// ─────────────────────────────────────────────────────────────────────────────

export const setConnected = (connected: boolean, sessionId?: string) => {
  store.setState({ connected, sessionId: sessionId ?? null })
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

export const setEvaluating = (isEvaluating: boolean) => {
  store.setState({ isEvaluating })
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
