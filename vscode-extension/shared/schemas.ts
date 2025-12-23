import { z } from "zod"

// ─────────────────────────────────────────────────────────────────────────────
// Exception Schema
// ─────────────────────────────────────────────────────────────────────────────

export const ExceptionInfoSchema = z.object({
  class: z.string(),
  message: z.string(),
  backtrace: z.array(z.string()),
})

// ─────────────────────────────────────────────────────────────────────────────
// Response Schemas
// ─────────────────────────────────────────────────────────────────────────────

export const EvalResultSchema = z.object({
  value: z.string(),
  valueType: z.string().optional(),
  stdout: z.string(),
  stderr: z.string(),
  exception: ExceptionInfoSchema.optional(),
})

export const SessionCreateResultSchema = z.object({
  sessionId: z.string(),
})

export const ServerInfoSchema = z.object({
  name: z.string(),
  version: z.string(),
})

export const CapabilitiesSchema = z.object({
  supportsInterrupt: z.boolean(),
})

export const InitializeResultSchema = z.object({
  serverInfo: ServerInfoSchema,
  capabilities: CapabilitiesSchema,
})

export const InterruptResultSchema = z.object({
  success: z.boolean(),
})

// ─────────────────────────────────────────────────────────────────────────────
// Notification Params Schemas
// ─────────────────────────────────────────────────────────────────────────────

export const StdoutParamsSchema = z.object({
  sessionId: z.string(),
  chunk: z.string(),
})

export const StderrParamsSchema = z.object({
  sessionId: z.string(),
  chunk: z.string(),
})

export const StatusParamsSchema = z.object({
  sessionId: z.string(),
  busy: z.boolean(),
})

// ─────────────────────────────────────────────────────────────────────────────
// Extension ↔ Webview Message Schemas
// ─────────────────────────────────────────────────────────────────────────────

export const ExtensionToWebviewSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("connected"), sessionId: z.string() }),
  z.object({ type: z.literal("disconnected"), reason: z.string().optional() }),
  z.object({ type: z.literal("result"), data: EvalResultSchema }),
  z.object({ type: z.literal("error"), message: z.string() }),
  z.object({ type: z.literal("notification"), method: z.string(), params: z.unknown() }),
  z.object({ type: z.literal("clear") }),
])

export const WebviewToExtensionSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("ready") }),
  z.object({ type: z.literal("eval"), code: z.string() }),
  z.object({ type: z.literal("interrupt") }),
  z.object({ type: z.literal("clear") }),
  z.object({ type: z.literal("connect") }),
  z.object({ type: z.literal("disconnect") }),
])

// ─────────────────────────────────────────────────────────────────────────────
// Parser Functions
// ─────────────────────────────────────────────────────────────────────────────

export const parseExtensionToWebview = (data: unknown) =>
  ExtensionToWebviewSchema.safeParse(data)

export const parseWebviewToExtension = (data: unknown) =>
  WebviewToExtensionSchema.safeParse(data)

// ─────────────────────────────────────────────────────────────────────────────
// Inferred Types (for convenience)
// ─────────────────────────────────────────────────────────────────────────────

export type ParsedExtensionToWebview = z.infer<typeof ExtensionToWebviewSchema>
export type ParsedWebviewToExtension = z.infer<typeof WebviewToExtensionSchema>
export type ParsedEvalResult = z.infer<typeof EvalResultSchema>
export type ParsedExceptionInfo = z.infer<typeof ExceptionInfoSchema>
