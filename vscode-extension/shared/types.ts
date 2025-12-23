// ─────────────────────────────────────────────────────────────────────────────
// Protocol Methods
// ─────────────────────────────────────────────────────────────────────────────

export enum Method {
  // Lifecycle (LSP-style)
  Initialize = "initialize",
  Shutdown = "shutdown",
  Exit = "exit",
  CancelRequest = "$/cancelRequest",

  // Konsol methods
  SessionCreate = "konsol/session.create",
  Eval = "konsol/eval",
  Interrupt = "konsol/interrupt",

  // Server notifications (server → client)
  Stdout = "konsol/stdout",
  Stderr = "konsol/stderr",
  Status = "konsol/status",
}

export const isNotificationMethod = (method: Method): boolean => {
  return [Method.Exit, Method.Stdout, Method.Stderr, Method.Status].includes(method)
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Codes
// ─────────────────────────────────────────────────────────────────────────────

export enum ErrorCode {
  // Standard JSON-RPC
  ParseError = -32700,
  InvalidRequest = -32600,
  MethodNotFound = -32601,
  InvalidParams = -32602,
  InternalError = -32603,

  // Konsol-specific
  SessionNotFound = -32001,
  SessionBusy = -32002,
  RailsBootFailed = -32003,
  EvalTimeout = -32004,
  ServerShuttingDown = -32005,
}

export const ErrorMessage: Record<ErrorCode, string> = {
  [ErrorCode.ParseError]: "Invalid JSON",
  [ErrorCode.InvalidRequest]: "Not a valid request object",
  [ErrorCode.MethodNotFound]: "Method does not exist",
  [ErrorCode.InvalidParams]: "Invalid method parameters",
  [ErrorCode.InternalError]: "Internal server error",
  [ErrorCode.SessionNotFound]: "Session ID does not exist",
  [ErrorCode.SessionBusy]: "Session is currently evaluating",
  [ErrorCode.RailsBootFailed]: "Failed to boot Rails environment",
  [ErrorCode.EvalTimeout]: "Evaluation timed out",
  [ErrorCode.ServerShuttingDown]: "Server is shutting down",
}

// ─────────────────────────────────────────────────────────────────────────────
// Protocol Types
// ─────────────────────────────────────────────────────────────────────────────

export type ErrorData = {
  code: ErrorCode
  message: string
  data?: Record<string, unknown>
}

export type ExceptionInfo = {
  class: string
  message: string
  backtrace: string[]
}

// ─────────────────────────────────────────────────────────────────────────────
// Request/Response Types
// ─────────────────────────────────────────────────────────────────────────────

export type ClientInfo = {
  name: string
  version?: string
}

export type ServerInfo = {
  name: string
  version: string
}

export type Capabilities = {
  supportsInterrupt: boolean
}

export type InitializeParams = {
  processId?: number | null
  clientInfo?: ClientInfo
}

export type InitializeResult = {
  serverInfo: ServerInfo
  capabilities: Capabilities
}

export type SessionCreateResult = {
  sessionId: string
}

export type EvalParams = {
  sessionId: string
  code: string
}

export type EvalResult = {
  value: string
  valueType?: string
  stdout: string
  stderr: string
  exception?: ExceptionInfo
}

export type InterruptParams = {
  sessionId: string
}

export type InterruptResult = {
  success: boolean
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Types
// ─────────────────────────────────────────────────────────────────────────────

export type StdoutParams = {
  sessionId: string
  chunk: string
}

export type StderrParams = {
  sessionId: string
  chunk: string
}

export type StatusParams = {
  sessionId: string
  busy: boolean
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension ↔ Webview Communication
// ─────────────────────────────────────────────────────────────────────────────

export type ExtensionToWebview =
  | { type: "connected", sessionId: string }
  | { type: "disconnected", reason?: string }
  | { type: "result", data: EvalResult }
  | { type: "error", message: string }
  | { type: "notification", method: string, params: unknown }
  | { type: "clear" }

export type WebviewToExtension =
  | { type: "ready" }
  | { type: "eval", code: string }
  | { type: "interrupt" }
  | { type: "clear" }
  | { type: "disconnect" }

// ─────────────────────────────────────────────────────────────────────────────
// Output Entry (for webview state)
// ─────────────────────────────────────────────────────────────────────────────

export type OutputEntryType = "prompt" | "result" | "error" | "stdout" | "stderr"

export type OutputEntry = {
  id: string
  type: OutputEntryType
  content: string
  timestamp: Date
}
