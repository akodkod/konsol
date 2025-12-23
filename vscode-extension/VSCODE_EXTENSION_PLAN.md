# VSCode Extension Plan for Konsol

This document outlines the architecture and approach for building a VSCode extension that serves as a client for the Konsol gem — a JSON-RPC 2.0 Rails console backend.

---

## Overview

The extension provides a **custom terminal-like bottom panel** in VSCode for Rails projects. It features:

- **Code input** with Ruby autocomplete/intellisense (via Ruby LSP)
- **Output display** showing evaluation results, stdout, stderr, and exceptions
- **Session management** with persistent state across evaluations

---

## Tech Stack

| Layer                 | Technology                    | Purpose                                              |
|-----------------------|-------------------------------|------------------------------------------------------|
| **Package Manager**   | pnpm                          | Fast, efficient disk usage, strict dependencies      |
| **Extension Host**    | TypeScript                    | VSCode extension runtime (Node.js)                   |
| **Webview UI**        | React 19                      | Component-based UI with native web component support |
| **State Management**  | Zustand                       | Lightweight global store for webview state           |
| **Schema Validation** | Zod                           | Runtime validation + TypeScript type inference       |
| **Code Editor**       | Monaco + @monaco-editor/react | Rich code input with syntax highlighting             |
| **UI Components**     | vscode-elements               | Native VSCode look via web components                |
| **Communication**     | vscode-jsonrpc                | JSON-RPC 2.0 with LSP framing                        |
| **Pattern Matching**  | ts-pattern                    | Exhaustive type-safe pattern matching                |
| **Build Tool**        | esbuild                       | Fast bundling for extension and webview              |

### Why These Choices

- **React 19**: Native web component support — use `<vscode-button>` directly without wrappers
- **Zustand**: Minimal boilerplate, works great with React, easy persistence via `getState()`/`setState()`
- **Zod**: Runtime validation of JSON-RPC messages with automatic TypeScript type inference via `z.infer<>`
- **ts-pattern**: Exhaustive pattern matching for handling discriminated unions (Message types) with full type inference
- **pnpm**: Fast package manager with efficient disk usage and strict dependency resolution

### TypeScript Conventions

- **Prefer `type` over `interface`**: Use `type` for all type definitions
- **No semicolons**: Omit trailing semicolons at end of lines
- **Full variable names**: Use descriptive names like `store((state) => state.messages)` instead of `store((s) => s.messages)`
- **No default exports**: Use named exports only

---

## Architecture: WebviewView Panel with Monaco

Use VSCode's `WebviewViewProvider` API to create a custom view in the bottom panel area.

```
┌─────────────────────────────────────────────────────────────────┐
│  VSCode Editor                                                  │
├─────────────────────────────────────────────────────────────────┤
│  [Terminal] [Problems] [Output] [Konsol]  ← Panel tabs          │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ > User.count                                                ││
│  │ => 42                                                       ││
│  │ > User.first.name                                           ││
│  │ => "Alice"                                                  ││
│  │ > puts "Hello"                                              ││
│  │ Hello                                                       ││
│  │ => nil                                                      ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ irb> _                                              [Run ▶] ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

**Why this approach:**
- Native VSCode integration (appears alongside Terminal, Problems, Output)
- Full HTML/CSS/JS flexibility for UI
- Can embed Monaco editor for code input
- Standard VSCode panel behavior (drag, resize, split)

**Trade-offs:**
- Monaco in webview is isolated from main VSCode (no shared settings/themes)
- Requires custom autocomplete implementation (solved via LSP delegation)

### High-Level Components

```
┌──────────────────────────────────────────────────────────────────────┐
│                        VSCode Extension Host                          │
│  ┌────────────────┐  ┌─────────────────┐  ┌───────────────────────┐  │
│  │   Extension    │  │  Konsol Client  │  │  Completion Provider  │  │
│  │   Activation   │──│  (JSON-RPC)     │  │  (LSP Delegation)     │  │
│  └───────┬────────┘  └────────┬────────┘  └───────────┬───────────┘  │
│          │                    │                       │              │
│  ┌───────┴────────────────────┴───────────────────────┴───────────┐  │
│  │                    WebviewViewProvider                          │  │
│  │  ┌──────────────────────────────────────────────────────────┐  │  │
│  │  │                    Webview (HTML/JS)                      │  │  │
│  │  │  ┌─────────────────┐  ┌──────────────────────────────┐   │  │  │
│  │  │  │  Output Display │  │  Monaco Editor (Input)       │   │  │  │
│  │  │  │  (Messages)     │  │  - Ruby syntax highlighting  │   │  │  │
│  │  │  │                 │  │  - Custom completion provider│   │  │  │
│  │  │  └─────────────────┘  └──────────────────────────────┘   │  │  │
│  │  └──────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ stdin/stdout (JSON-RPC 2.0)
                                    │ LSP-style framing
                                    ▼
                    ┌──────────────────────────────┐
                    │     konsol --stdio           │
                    │     (Child Process)          │
                    │     - Session management     │
                    │     - Code evaluation        │
                    │     - Rails integration      │
                    └──────────────────────────────┘
```

---

## Component Details

### 1. Extension Entry Point (`extension.ts`)

```typescript
// Activation events:
// - workspaceContains:**/config/environment.rb (more specific than Gemfile)
// - onView:konsol.panel
// - onCommand:konsol.start

export function activate(context: vscode.ExtensionContext) {
  // Register WebviewViewProvider for bottom panel
  const provider = new KonsolViewProvider(context.extensionUri)
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider('konsol.panel', provider, {
      webviewOptions: { retainContextWhenHidden: true }
    })
  )

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('konsol.start', () => provider.start()),
    vscode.commands.registerCommand('konsol.stop', () => provider.stop()),
    vscode.commands.registerCommand('konsol.clear', () => provider.clear())
  )
}
```

### 2. Konsol Client (`konsol-client.ts`)

Uses `vscode-jsonrpc` for JSON-RPC communication over stdio:

```typescript
import * as cp from 'child_process'
import * as rpc from 'vscode-jsonrpc/node'

class KonsolClient {
  private process: cp.ChildProcess | null = null
  private connection: rpc.MessageConnection | null = null
  private sessionId: string | null = null

  async start(workspaceRoot: string): Promise<void> {
    // Spawn konsol process
    this.process = cp.spawn('bundle', ['exec', 'konsol', '--stdio'], {
      cwd: workspaceRoot,
      env: { ...process.env, RAILS_ENV: 'development' }
    })

    // Create JSON-RPC connection with LSP-style framing
    this.connection = rpc.createMessageConnection(
      new rpc.StreamMessageReader(this.process.stdout!),
      new rpc.StreamMessageWriter(this.process.stdin!)
    )

    this.connection.listen()

    // Initialize
    await this.connection.sendRequest('initialize', {
      clientInfo: { name: 'vscode-konsol', version: '0.1.0' }
    })

    // Create session
    const result = await this.connection.sendRequest('konsol/session.create', {})
    this.sessionId = result.sessionId
  }

  async eval(code: string): Promise<EvalResult> {
    return this.connection!.sendRequest('konsol/eval', {
      sessionId: this.sessionId,
      code
    })
  }

  async shutdown(): Promise<void> {
    await this.connection?.sendRequest('shutdown')
    this.connection?.sendNotification('exit')
    this.process?.kill()
  }
}
```

### 3. WebviewViewProvider (`konsol-view-provider.ts`)

Manages the webview panel lifecycle and communication:

```typescript
class KonsolViewProvider implements vscode.WebviewViewProvider {
  private view?: vscode.WebviewView
  private client?: KonsolClient

  resolveWebviewView(webviewView: vscode.WebviewView) {
    this.view = webviewView

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri]
    }

    webviewView.webview.html = this.getHtmlContent()

    // Handle messages from webview
    webviewView.webview.onDidReceiveMessage(async (message) => {
      switch (message.type) {
        case 'eval':
          const result = await this.client?.eval(message.code)
          this.view?.webview.postMessage({ type: 'result', data: result })
          break
        case 'requestCompletion':
          const completions = await this.getCompletions(message.code, message.position)
          this.view?.webview.postMessage({ type: 'completions', data: completions })
          break
      }
    })
  }
}
```

### 4. Webview UI (React 19 + Zustand)

The webview is a React 19 application with Zustand for state management.

#### HTML Template (`webview/index.html`)

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="
    default-src 'none';
    style-src ${webview.cspSource} 'unsafe-inline';
    script-src 'nonce-${nonce}';
    font-src ${webview.cspSource};
    img-src ${webview.cspSource} data:;
  ">
  <link rel="stylesheet" href="${stylesUri}">
  <link rel="stylesheet" href="${codiconsUri}">
  <title>Konsol</title>
</head>
<body>
  <div id="root"></div>
  <script nonce="${nonce}" src="${mainScriptUri}"></script>
</body>
</html>
```

#### Zustand Store (`webview/stores/konsol-store.ts`)

The store is **encapsulated** — only hooks and mutators are exported, never the store itself. This enforces controlled access patterns and makes the API surface explicit.

Raw protocol messages (Request, Response, Notification) are stored directly without transformation.

```typescript
import { create } from 'zustand'
import type { Message } from '../../shared/types'

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

type KonsolState = {
  // Connection
  connected: boolean
  sessionId: string | null

  // Messages (raw protocol messages)
  messages: Message[]

  // Command history for up/down navigation
  commandHistory: string[]
  commandHistoryIndex: number

  // UI state
  isEvaluating: boolean
}

// ─────────────────────────────────────────────────────────────────────────────
// Store (private — NOT exported)
// ─────────────────────────────────────────────────────────────────────────────

const store = create<KonsolState>()(() => ({
  connected: false,
  sessionId: null,
  messages: [],
  commandHistory: [],
  commandHistoryIndex: -1,
  isEvaluating: false,
}))

// ─────────────────────────────────────────────────────────────────────────────
// Selectors (exported hooks)
// ─────────────────────────────────────────────────────────────────────────────

export const useConnected = () => store((state) => state.connected)
export const useSessionId = () => store((state) => state.sessionId)
export const useMessages = () => store((state) => state.messages)
export const useCommandHistory = () => store((state) => state.commandHistory)
export const useCommandHistoryIndex = () => store((state) => state.commandHistoryIndex)
export const useIsEvaluating = () => store((state) => state.isEvaluating)

// ─────────────────────────────────────────────────────────────────────────────
// Mutators (exported actions)
// ─────────────────────────────────────────────────────────────────────────────

export const setConnected = (connected: boolean, sessionId?: string) => {
  store.setState({ connected, sessionId: sessionId ?? null })
}

export const addMessage = (message: Message) => {
  store.setState((state) => ({
    messages: [...state.messages, message],
  }))
}

export const addCommand = (code: string) => {
  store.setState((state) => ({
    commandHistory: [...state.commandHistory, code],
    commandHistoryIndex: -1,
  }))
}

export const clearMessages = () => {
  store.setState({ messages: [], commandHistoryIndex: -1 })
}

export const setEvaluating = (isEvaluating: boolean) => {
  store.setState({ isEvaluating })
}

export const navigateCommandHistory = (direction: 'up' | 'down'): string | null => {
  const { commandHistory, commandHistoryIndex } = store.getState()
  if (commandHistory.length === 0) return null

  let newIndex: number
  if (direction === 'up') {
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
```

**Benefits of this pattern:**
- Store internals are encapsulated — no direct access to `set()` or `get()`
- Components only import what they need: `useMessages()`, `addMessage()`, etc.
- Raw protocol messages stored without transformation
- Mutators can be used outside React components (e.g., in message handlers)
- Easier to test — mock individual functions instead of the whole store
- Clear separation: hooks for reading, functions for writing

#### React Entry (`webview/main.tsx`)

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import './styles/konsol.css'

// Import vscode-elements (React 19 native web component support)
import '@vscode-elements/elements/dist/vscode-button'
import '@vscode-elements/elements/dist/vscode-icon'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
)
```

#### App Component (`webview/App.tsx`)

```tsx
import { useEffect } from 'react'
import { match } from 'ts-pattern'
import { Output } from './components/Output'
import { Editor } from './components/Editor'
import { StatusBar } from './components/StatusBar'
import {
  setConnected,
  addMessage,
  addCommand,
  setEvaluating,
} from './stores/konsol-store'
import { vscode } from './lib/vscode-api'
import { buildMessageFromRaw } from '../../shared/message-builder'
import { Method, type Message, type ExtensionToWebview } from '../../shared/types'
import { parseExtensionToWebview } from '../../shared/schemas'

export function App() {
  useEffect(() => {
    const handleExtensionMessage = (event: MessageEvent<ExtensionToWebview>) => {
      const parsed = parseExtensionToWebview(event.data)
      if (!parsed.success) return

      match(parsed.data)
        .with({ type: 'connected' }, ({ sessionId }) => {
          setConnected(true, sessionId)
        })
        .with({ type: 'disconnected' }, ({ reason }) => {
          setConnected(false)
          // Optionally show disconnect reason
        })
        .with({ type: 'message' }, ({ data }) => {
          // Build enriched Message from raw JSON-RPC
          const message = buildMessageFromRaw(data)
          addMessage(message)
          handleMessage(message)
        })
        .exhaustive()
    }

    window.addEventListener('message', handleExtensionMessage)
    vscode.postMessage({ type: 'ready' })

    return () => window.removeEventListener('message', handleExtensionMessage)
  }, [])

  // Handle side effects based on message type using ts-pattern
  const handleMessage = (message: Message) => {
    match(message)
      .with({ type: 'response', method: Method.SessionCreate }, (msg) => {
        if (!msg.error && msg.body) {
          setConnected(true, msg.body.sessionId)
        }
      })
      .with({ type: 'response', method: Method.Eval }, (msg) => {
        setEvaluating(false)
        // msg.body is typed as EvalResult | undefined
        // msg.error is typed as ErrorData | undefined
      })
      .with({ type: 'response', method: Method.Interrupt }, () => {
        setEvaluating(false)
      })
      .with({ type: 'notification', method: Method.Status }, (msg) => {
        // msg.body is typed as { sessionId: string, busy: boolean }
        setEvaluating(msg.body.busy)
      })
      .with({ type: 'notification', method: Method.Stdout }, (msg) => {
        // Handle stdout chunk: msg.body.chunk
      })
      .with({ type: 'notification', method: Method.Stderr }, (msg) => {
        // Handle stderr chunk: msg.body.chunk
      })
      .otherwise(() => {
        // Other messages (initialize response, etc.)
      })
  }

  const handleEval = (code: string) => {
    if (!code.trim()) return
    addCommand(code)
    setEvaluating(true)
    // Send simplified message - extension creates structured request ID
    vscode.postMessage({ type: 'eval', code })
  }

  return (
    <div className="konsol-container">
      <Output />
      <Editor onEval={handleEval} />
      <StatusBar />
    </div>
  )
}
```

#### Editor Component with Monaco (`webview/components/Editor.tsx`)

```tsx
import { useRef, useCallback } from 'react'
import MonacoEditor, { type OnMount } from '@monaco-editor/react'
import { useIsEvaluating, navigateCommandHistory } from '../stores/konsol-store'

type EditorProps = {
  onEval: (code: string) => void
}

export function Editor({ onEval }: EditorProps) {
  const editorRef = useRef<any>(null)
  const isEvaluating = useIsEvaluating()

  const handleMount: OnMount = (editor, monaco) => {
    editorRef.current = editor

    // Ctrl/Cmd+Enter to evaluate
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, () => {
      const code = editor.getValue()
      onEval(code)
      editor.setValue('')
    })

    // Up arrow for history
    editor.addCommand(monaco.KeyCode.UpArrow, () => {
      const prev = navigateCommandHistory('up')
      if (prev !== null) editor.setValue(prev)
    })

    // Down arrow for history
    editor.addCommand(monaco.KeyCode.DownArrow, () => {
      const next = navigateCommandHistory('down')
      if (next !== null) editor.setValue(next)
    })

    editor.focus()
  }

  const handleRun = useCallback(() => {
    if (editorRef.current) {
      const code = editorRef.current.getValue()
      onEval(code)
      editorRef.current.setValue('')
    }
  }, [onEval])

  return (
    <div className="konsol-input-wrapper">
      <div className="konsol-editor">
        <MonacoEditor
          height="60px"
          language="ruby"
          theme="vs-dark"
          options={{
            minimap: { enabled: false },
            lineNumbers: 'off',
            glyphMargin: false,
            folding: false,
            lineDecorationsWidth: 0,
            lineNumbersMinChars: 0,
            scrollBeyondLastLine: false,
            automaticLayout: true,
            fontSize: 14,
            fontFamily: 'var(--vscode-editor-font-family)',
          }}
          onMount={handleMount}
        />
      </div>
      {/* React 19: native web component support */}
      <vscode-button
        appearance="icon"
        class="konsol-run-btn"
        disabled={isEvaluating}
        onClick={handleRun}
        title="Run (Ctrl+Enter)"
      >
        <span className="codicon codicon-play" />
      </vscode-button>
    </div>
  )
}
```

#### Output Component (`webview/components/Output.tsx`)

```tsx
import { useEffect, useRef } from 'react'
import { useMessages } from '../stores/konsol-store'
import { MessageRow } from './MessageRow'

export function Output() {
  const messages = useMessages()
  const bottomRef = useRef<HTMLDivElement>(null)

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  return (
    <div className="konsol-output">
      {messages.map((message, index) => (
        <MessageRow key={index} message={message} />
      ))}
      <div ref={bottomRef} />
    </div>
  )
}
```

#### VSCode API Wrapper (`webview/lib/vscode-api.ts`)

```typescript
type VSCodeAPI = {
  postMessage: (message: unknown) => void
  getState: () => unknown
  setState: (state: unknown) => void
}

// Acquire once, reuse everywhere
export const vscode: VSCodeAPI = acquireVsCodeApi()
```

#### Styling (`webview/styles/konsol.css`)

```css
/* Uses native VSCode theme colors - see VSCODE_EXTENSION_BEST_PRACTICES.md */
.konsol-container {
  height: 100%;
  display: flex;
  flex-direction: column;
  background: var(--vscode-panel-background);
  color: var(--vscode-foreground);
  font-family: var(--vscode-editor-font-family), monospace;
  font-size: var(--vscode-editor-font-size);
}

.konsol-output {
  flex: 1;
  overflow-y: auto;
  padding: 8px 12px;
}

.konsol-input-wrapper {
  display: flex;
  align-items: center;
  gap: 4px;
  border-top: 1px solid var(--vscode-panel-border);
  padding: 8px;
  background: var(--vscode-input-background);
}

.konsol-editor {
  flex: 1;
}

/* Terminal-style output colors */
.konsol-prompt  { color: var(--vscode-terminal-ansiGreen); }
.konsol-result  { color: var(--vscode-terminal-ansiBrightBlue); }
.konsol-error   { color: var(--vscode-terminal-ansiRed); }
.konsol-stdout  { color: var(--vscode-terminal-foreground); }
.konsol-stderr  { color: var(--vscode-terminal-ansiYellow); }
```

---

### 5. Shared Protocol Types

Types are organized into two files with a new **enriched Message type** for the webview:
- `shared/types.ts` — TypeScript types matching the konsol gem's Sorbet structs
- `shared/schemas.ts` — Zod schemas for runtime validation with inferred types

All JSON keys use **camelCase** (converted from Ruby's snake_case at protocol boundary).

#### Method Enum (`shared/types.ts`)

```typescript
/**
 * JSON-RPC method names - must match Konsol::Protocol::Method enum
 * Uses const object pattern for better tree-shaking and string literal types
 */
export enum Method {
  // Lifecycle (LSP-style)
  Initialize = 'initialize',
  Shutdown = 'shutdown',
  Exit = 'exit',
  CancelRequest = '$/cancelRequest',

  // Konsol methods
  SessionCreate = 'konsol/session.create',
  Eval = 'konsol/eval',
  Interrupt = 'konsol/interrupt',

  // Server notifications (server → client)
  Stdout = 'konsol/stdout',
  Stderr = 'konsol/stderr',
  Status = 'konsol/status',
}

/**
 * Check if a method is a notification (fire-and-forget)
 */
export const isNotificationMethod = (method: Method): boolean => {
  return [Method.Exit, Method.Stdout, Method.Stderr, Method.Status].includes(method)
}
```

#### Error Codes

```typescript
/**
 * JSON-RPC error codes - must match Konsol::Protocol::ErrorCode enum
 */
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
  [ErrorCode.ParseError]: 'Invalid JSON',
  [ErrorCode.InvalidRequest]: 'Not a valid request object',
  [ErrorCode.MethodNotFound]: 'Method does not exist',
  [ErrorCode.InvalidParams]: 'Invalid method parameters',
  [ErrorCode.InternalError]: 'Internal server error',
  [ErrorCode.SessionNotFound]: 'Session ID does not exist',
  [ErrorCode.SessionBusy]: 'Session is currently evaluating',
  [ErrorCode.RailsBootFailed]: 'Failed to boot Rails environment',
  [ErrorCode.EvalTimeout]: 'Evaluation timed out',
  [ErrorCode.ServerShuttingDown]: 'Server is shutting down',
}
```

#### Base Message Type

The webview stores **enriched messages** with metadata for display, not raw JSON-RPC:

```typescript
/**
 * Base message type for webview state
 * All messages stored in the webview include this metadata
 */
type BaseMessage = {
  id: string           // Unique message ID (UUID part of structured request ID)
  method: Method       // The JSON-RPC method
  type: 'request' | 'response' | 'notification'
  date: Date           // Timestamp for display
}

/**
 * JSON-RPC error data
 */
export type ErrorData = {
  code: ErrorCode
  message: string
  data?: Record<string, unknown>
}
```

#### Zod Schemas for Request/Response Bodies (`shared/schemas.ts`)

```typescript
import { z } from 'zod'

// ─────────────────────────────────────────────────────────────────────────────
// Request Params Schemas
// ─────────────────────────────────────────────────────────────────────────────

export const ClientInfoSchema = z.object({
  name: z.string(),
  version: z.string().optional(),
})

export const InitializeParamsSchema = z.object({
  processId: z.number().nullable().optional(),
  clientInfo: ClientInfoSchema.optional(),
})

export const SessionCreateParamsSchema = z.object({})

export const EvalParamsSchema = z.object({
  sessionId: z.string(),
  code: z.string(),
})

export const InterruptParamsSchema = z.object({
  sessionId: z.string(),
})

export const CancelParamsSchema = z.object({
  id: z.union([z.string(), z.number()]),
})

export const ShutdownParamsSchema = z.object({})

// ─────────────────────────────────────────────────────────────────────────────
// Response Result Schemas
// ─────────────────────────────────────────────────────────────────────────────

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

export const SessionCreateResultSchema = z.object({
  sessionId: z.string(),
})

export const ExceptionInfoSchema = z.object({
  class: z.string(),
  message: z.string(),
  backtrace: z.array(z.string()),
})

export const EvalResultSchema = z.object({
  value: z.string(),
  valueType: z.string().nullable().optional(),
  stdout: z.string(),
  stderr: z.string(),
  exception: ExceptionInfoSchema.nullable().optional(),
})

export const InterruptResultSchema = z.object({
  success: z.boolean(),
})

// ─────────────────────────────────────────────────────────────────────────────
// Notification Params Schemas
// ─────────────────────────────────────────────────────────────────────────────

export const ExitParamsSchema = z.object({})

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
```

#### Typed Message Types

Each message type combines `BaseMessage` with method-specific body:

```typescript
// ─────────────────────────────────────────────────────────────────────────────
// Request Messages
// ─────────────────────────────────────────────────────────────────────────────

type InitializeRequestMessage = BaseMessage & {
  method: Method.Initialize
  type: 'request'
  body: z.infer<typeof InitializeParamsSchema>
}

type SessionCreateRequestMessage = BaseMessage & {
  method: Method.SessionCreate
  type: 'request'
  body: z.infer<typeof SessionCreateParamsSchema>
}

type EvalRequestMessage = BaseMessage & {
  method: Method.Eval
  type: 'request'
  body: z.infer<typeof EvalParamsSchema>
}

type InterruptRequestMessage = BaseMessage & {
  method: Method.Interrupt
  type: 'request'
  body: z.infer<typeof InterruptParamsSchema>
}

type CancelRequestMessage = BaseMessage & {
  method: Method.CancelRequest
  type: 'request'
  body: z.infer<typeof CancelParamsSchema>
}

type ShutdownRequestMessage = BaseMessage & {
  method: Method.Shutdown
  type: 'request'
  body: z.infer<typeof ShutdownParamsSchema>
}

// ─────────────────────────────────────────────────────────────────────────────
// Response Messages (include optional error)
// ─────────────────────────────────────────────────────────────────────────────

type InitializeResponseMessage = BaseMessage & {
  method: Method.Initialize
  type: 'response'
  body?: z.infer<typeof InitializeResultSchema>
  error?: ErrorData
}

type SessionCreateResponseMessage = BaseMessage & {
  method: Method.SessionCreate
  type: 'response'
  body?: z.infer<typeof SessionCreateResultSchema>
  error?: ErrorData
}

type EvalResponseMessage = BaseMessage & {
  method: Method.Eval
  type: 'response'
  body?: z.infer<typeof EvalResultSchema>
  error?: ErrorData
}

type InterruptResponseMessage = BaseMessage & {
  method: Method.Interrupt
  type: 'response'
  body?: z.infer<typeof InterruptResultSchema>
  error?: ErrorData
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Messages
// ─────────────────────────────────────────────────────────────────────────────

type StdoutNotificationMessage = BaseMessage & {
  method: Method.Stdout
  type: 'notification'
  body: z.infer<typeof StdoutParamsSchema>
}

type StderrNotificationMessage = BaseMessage & {
  method: Method.Stderr
  type: 'notification'
  body: z.infer<typeof StderrParamsSchema>
}

type StatusNotificationMessage = BaseMessage & {
  method: Method.Status
  type: 'notification'
  body: z.infer<typeof StatusParamsSchema>
}

type ExitNotificationMessage = BaseMessage & {
  method: Method.Exit
  type: 'notification'
  body: z.infer<typeof ExitParamsSchema>
}

// ─────────────────────────────────────────────────────────────────────────────
// Union Type
// ─────────────────────────────────────────────────────────────────────────────

export type Message =
  // Requests
  | InitializeRequestMessage
  | SessionCreateRequestMessage
  | EvalRequestMessage
  | InterruptRequestMessage
  | CancelRequestMessage
  | ShutdownRequestMessage
  // Responses
  | InitializeResponseMessage
  | SessionCreateResponseMessage
  | EvalResponseMessage
  | InterruptResponseMessage
  // Notifications
  | StdoutNotificationMessage
  | StderrNotificationMessage
  | StatusNotificationMessage
  | ExitNotificationMessage
```

#### Request ID Structure

Use structured request IDs to embed the method name, enabling response → method tracking:

```typescript
// Format: "method:uuid" e.g. "konsol/eval:550e8400-e29b-41d4-a716-446655440000"

export function createRequestId(method: Method): string {
  return `${method}:${crypto.randomUUID()}`
}

export function parseRequestId(id: string): { method: Method, uuid: string } {
  const lastColon = id.lastIndexOf(':')
  return {
    method: id.slice(0, lastColon) as Method,
    uuid: id.slice(lastColon + 1),
  }
}
```

#### Message Builder Function (`shared/message-builder.ts`)

Converts raw JSON-RPC messages to enriched `Message` type:

```typescript
import { match } from 'ts-pattern'
import { Method, parseRequestId, type Message, type ErrorData } from './types'
import {
  EvalResultSchema,
  SessionCreateResultSchema,
  InitializeResultSchema,
  InterruptResultSchema,
  StdoutParamsSchema,
  StderrParamsSchema,
  StatusParamsSchema,
} from './schemas'

type RawJsonRpcMessage = {
  jsonrpc: '2.0'
  id?: string | number | null
  method?: string
  params?: unknown
  result?: unknown
  error?: ErrorData
}

export function buildMessageFromRaw(raw: RawJsonRpcMessage): Message {
  const date = new Date()

  // Response - parse method from structured ID
  if (raw.id != null && ('result' in raw || 'error' in raw)) {
    const { method, uuid } = parseRequestId(raw.id as string)

    const schemaMap = {
      [Method.Initialize]: InitializeResultSchema,
      [Method.SessionCreate]: SessionCreateResultSchema,
      [Method.Eval]: EvalResultSchema,
      [Method.Interrupt]: InterruptResultSchema,
    } as const

    const schema = schemaMap[method as keyof typeof schemaMap]

    if (schema) {
      return {
        id: uuid,
        method,
        type: 'response' as const,
        date,
        body: raw.error ? undefined : schema.parse(raw.result),
        error: raw.error,
      }
    }
    
    throw new Error(`Unknown response method: ${method}`)
  }

  // Notification - method is in the message
  if (raw.method && raw.id == null) {
    const id = crypto.randomUUID()

    const notificationSchemas = {
      [Method.Stdout]: StdoutParamsSchema,
      [Method.Stderr]: StderrParamsSchema,
      [Method.Status]: StatusParamsSchema,
    } as const

    if (raw.method === Method.Exit) {
      return {
        id,
        method: Method.Exit,
        type: 'notification' as const,
        date,
        body: {},
      }
    }

    const schema = notificationSchemas[raw.method as keyof typeof notificationSchemas]

    if (schema) {
      return {
        id,
        method: raw.method,
        type: 'notification' as const,
        date,
        body: schema.parse(raw.params),
      }
    }

    throw new Error(`Unknown notification method: ${raw.method}`)
  }

  throw new Error('Invalid JSON-RPC message structure')
}
```

#### Extension ↔ Webview Communication

The extension host forwards raw JSON-RPC messages between the konsol server and webview. Control messages handle lifecycle:

```typescript
// ─────────────────────────────────────────────────────────────────────────────
// Extension → Webview
// ─────────────────────────────────────────────────────────────────────────────

export type ExtensionToWebview =
  | { type: 'connected', sessionId: string }
  | { type: 'disconnected', reason?: string }
  | { type: 'message', data: RawJsonRpcMessage }

// ─────────────────────────────────────────────────────────────────────────────
// Webview → Extension
// ─────────────────────────────────────────────────────────────────────────────

export type WebviewToExtension =
  | { type: 'ready' }
  | { type: 'eval', code: string }      // Extension creates request with structured ID
  | { type: 'interrupt' }
  | { type: 'clear' }
```

#### Zod Schemas for Validation

```typescript
import { z } from 'zod'

// Extension ↔ Webview validation
export const ExtensionToWebviewSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('connected'), sessionId: z.string() }),
  z.object({ type: z.literal('disconnected'), reason: z.string().optional() }),
  z.object({ type: z.literal('message'), data: z.unknown() }),
])

export const WebviewToExtensionSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('ready') }),
  z.object({ type: z.literal('eval'), code: z.string() }),
  z.object({ type: z.literal('interrupt') }),
  z.object({ type: z.literal('clear') }),
])

export const parseExtensionToWebview = (data: unknown) =>
  ExtensionToWebviewSchema.safeParse(data)
export const parseWebviewToExtension = (data: unknown) =>
  WebviewToExtensionSchema.safeParse(data)
```

**Benefits of this design:**
- **Type-safe message handling**: `ts-pattern` provides exhaustive matching with full type inference
- **Enriched messages**: Each message has `id`, `method`, `type`, and `date` for display
- **Structured request IDs**: Format `method:uuid` enables tracking which method a response belongs to
- **Zod validation**: Runtime validation at protocol boundaries
- **Discriminated unions**: TypeScript narrows types based on `type` and `method` fields

---

## Package.json Configuration

```json
{
  "name": "vscode-konsol",
  "displayName": "Konsol - Rails Console",
  "description": "Interactive Rails console panel for VSCode",
  "version": "0.1.0",
  "engines": { "vscode": "^1.85.0" },
  "categories": ["Other", "Debuggers"],
  "activationEvents": [
    "workspaceContains:**/config/environment.rb"
  ],
  "main": "./dist/extension.js",
  "contributes": {
    "viewsContainers": {
      "panel": [
        {
          "id": "konsol-panel-container",
          "title": "Konsol",
          "icon": "$(terminal)"
        }
      ]
    },
    "views": {
      "konsol-panel-container": [
        {
          "type": "webview",
          "id": "konsol.panel",
          "name": "Rails Console",
          "contextualTitle": "Konsol"
        }
      ]
    },
    "commands": [
      {
        "command": "konsol.start",
        "title": "Start Konsol Session",
        "category": "Konsol"
      },
      {
        "command": "konsol.stop",
        "title": "Stop Konsol Session",
        "category": "Konsol"
      },
      {
        "command": "konsol.clear",
        "title": "Clear Console",
        "category": "Konsol"
      },
      {
        "command": "konsol.eval",
        "title": "Evaluate Selection in Konsol",
        "category": "Konsol"
      }
    ],
    "menus": {
      "editor/context": [
        {
          "command": "konsol.eval",
          "when": "editorHasSelection && resourceLangId == ruby",
          "group": "konsol"
        }
      ]
    },
    "keybindings": [
      {
        "command": "konsol.eval",
        "key": "ctrl+enter",
        "mac": "cmd+enter",
        "when": "activeWebviewPanelId == 'konsol.panel'"
      }
    ],
    "configuration": {
      "title": "Konsol",
      "properties": {
        "konsol.railsEnv": {
          "type": "string",
          "default": "development",
          "description": "Rails environment to use"
        },
        "konsol.autoStart": {
          "type": "boolean",
          "default": false,
          "description": "Automatically start Konsol when opening a Rails project"
        }
      }
    }
  },
  "dependencies": {
    "vscode-jsonrpc": "^8.2.0",
    "zod": "^3.23.0",
    "ts-pattern": "^5.6.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "zustand": "^5.0.0",
    "monaco-editor": "^0.52.0",
    "@monaco-editor/react": "^4.6.0",
    "@vscode-elements/elements": "^1.6.0",
    "@vscode/codicons": "^0.0.36"
  },
  "devDependencies": {
    "@types/vscode": "^1.85.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "typescript": "^5.3.0",
    "esbuild": "^0.27.0"
  }
}
```

---

## Project Structure

```
konsol/                           # VSCode extension root
├── package.json
├── pnpm-lock.yaml                # pnpm lockfile
├── tsconfig.json                 # Extension TypeScript config
├── tsconfig.webview.json         # Separate config for React webview (Phase 2+)
├── esbuild.js                    # esbuild build script
├── eslint.config.mjs             # ESLint flat config
├── .vscode-test.mjs              # VSCode test CLI configuration
│
├── .vscode/
│   ├── extensions.json           # Recommended extensions
│   ├── launch.json               # Debug configurations
│   ├── settings.json             # Workspace settings
│   └── tasks.json                # Build tasks
│
├── src/                          # Extension Host (Node.js)
│   ├── extension.ts              # Entry point, activation
│   ├── konsol-client.ts          # JSON-RPC client for konsol gem
│   ├── konsol-view-provider.ts   # WebviewViewProvider
│   ├── completion-provider.ts    # LSP delegation / custom completions
│   ├── virtual-document.ts       # Virtual document for LSP bridging
│   └── test/                     # Extension integration tests
│       └── extension.test.ts     # Mocha test suite
│
├── webview/                      # React 19 Webview (Browser) - Phase 2+
│   ├── index.html                # HTML template with React root
│   ├── main.tsx                  # React entry point
│   ├── App.tsx                   # Root component
│   ├── components/
│   │   ├── Output.tsx            # Messages display
│   │   ├── MessageRow.tsx        # Renders a single Message (Request/Response/Notification)
│   │   ├── Editor.tsx            # Monaco editor wrapper
│   │   ├── StatusBar.tsx         # Connection status, session info
│   │   └── Toolbar.tsx           # Run button, clear, etc.
│   ├── stores/
│   │   └── konsol-store.ts       # Zustand store for session state
│   ├── hooks/
│   │   ├── use-vscode-api.ts     # VSCode API hook
│   │   └── use-konsol.ts         # Konsol actions hook
│   ├── lib/
│   │   └── vscode-api.ts         # acquireVsCodeApi wrapper
│   └── styles/
│       └── konsol.css            # Styles using VSCode CSS variables
│
├── shared/                       # Shared between extension and webview
│   ├── types.ts                  # TypeScript types matching gem protocol
│   ├── schemas.ts                # Zod schemas for runtime validation
│   └── message-builder.ts        # Converts raw JSON-RPC to enriched Message
│
├── dist/                         # Build output (gitignored)
│   ├── extension.js              # Bundled extension
│   └── webview/                  # Bundled webview assets
│       └── main.js
│
├── out/                          # TypeScript compiled tests (gitignored)
│   └── test/
│       └── extension.test.js
│
└── resources/
    └── icons/
```

---

## Implementation Phases

### Phase 1a: Extension Skeleton
1. Project scaffolding with pnpm, TypeScript, esbuild
2. Extension host with WebviewViewProvider (static HTML)
3. Konsol process spawn with JSON-RPC connection
4. `initialize` handshake validation
5. Basic error handling for missing konsol gem

### Phase 1b: Basic Eval Flow
1. Simple webview UI with vanilla HTML/JS (no React yet)
2. `<textarea>` input + Run button
3. Single eval roundtrip: input → konsol → output display
4. Session create/destroy lifecycle
5. stdout/stderr output display

### Phase 1c: React Migration
1. Add React 19 + Zustand dependencies
2. Port webview to React components
3. Zustand store for state management
4. Zod validation for extension ↔ webview messages
5. vscode-elements integration

### Phase 2: Monaco Integration
1. Replace textarea with `@monaco-editor/react`
2. Bundle Monaco locally (not CDN) for CSP compliance
3. Ruby syntax highlighting
4. Multi-line input support
5. Command history (up/down arrows)
6. Keyboard shortcuts (Ctrl+Enter to run)

### Phase 3: Polish
1. Native theming with VSCode CSS variables
2. Rich output formatting (syntax-highlighted results)
3. Error stack trace links (click to open file)
4. Inline object inspection
5. Loading states and error handling

### Phase 4: Advanced Features
1. Multiple sessions (tabs)
2. Code snippets
3. History persistence (via `vscode.setState`)
4. "Eval selection" from editor (context menu)
5. Integration with Ruby debugger

### Future: Autocomplete / Intellisense
See [AUTOCOMPLETE_PLAN.md](./AUTOCOMPLETE_PLAN.md) for detailed implementation strategy.

---

## Testing

### Testing Stack

| Tool                    | Purpose                                   |
|-------------------------|-------------------------------------------|
| `@vscode/test-cli`      | CLI runner for VSCode extension tests     |
| `@vscode/test-electron` | Downloads and launches VSCode for testing |
| `Mocha`                 | Test framework (suite/test pattern)       |
| `assert`                | Node.js built-in assertions               |

### Test Categories

#### 1. Extension Integration Tests (`src/test/`)

Tests that run inside a VSCode instance with full API access.

**Location:** `src/test/extension.test.ts`

**What to test:**
- Extension activation
- Command registration and execution
- WebviewViewProvider creation
- Session lifecycle (start → eval → stop)
- Error handling for missing konsol gem

```typescript
import * as assert from 'assert'
import * as vscode from 'vscode'

suite('Extension Test Suite', () => {
  vscode.window.showInformationMessage('Start all tests.')

  test('Extension should be present', () => {
    assert.ok(vscode.extensions.getExtension('konsol.konsol'))
  })

  test('Extension should activate', async () => {
    const ext = vscode.extensions.getExtension('konsol.konsol')
    await ext?.activate()
    assert.strictEqual(ext?.isActive, true)
  })

  test('Commands should be registered', async () => {
    const commands = await vscode.commands.getCommands(true)
    assert.ok(commands.includes('konsol.start'))
    assert.ok(commands.includes('konsol.stop'))
    assert.ok(commands.includes('konsol.clear'))
  })
})
```

#### 2. Unit Tests (Future - when adding business logic)

For testing pure functions without VSCode API dependency.

**Location:** `src/test/unit/` (to be created)

**What to test:**
- Protocol message parsing/serialization
- Zod schema validation
- Case transformation (camelCase ↔ snake_case)
- Output formatting logic

```typescript
import { describe, it } from 'mocha'
import * as assert from 'assert'
import { parseExtensionMessage } from '../../shared/schemas'

describe('Message Parsing', () => {
  it('should parse valid connected message', () => {
    const result = parseExtensionMessage({
      type: 'connected',
      sessionId: 'abc-123'
    })
    assert.ok(result.success)
  })

  it('should reject invalid message', () => {
    const result = parseExtensionMessage({
      type: 'invalid'
    })
    assert.ok(!result.success)
  })
})
```

#### 3. Webview Tests (Phase 2+)

For testing React components and Zustand store.

**Location:** `webview/test/` (to be created)

**Tools:** Vitest + React Testing Library (runs in Node, not VSCode)

**What to test:**
- Zustand store state transitions
- Component rendering
- Message handling from extension
- User interactions (click, keyboard)

### Test Configuration

#### `.vscode-test.mjs`

```javascript
import { defineConfig } from '@vscode/test-cli'

export default defineConfig({
  files: 'out/test/**/*.test.js',
  // Optionally specify VSCode version
  // version: 'stable',
  // workspaceFolder: './test-fixtures/workspace',
  // extensionDevelopmentPath: '.',
})
```

#### Running Tests

```bash
# Run all tests (compiles first)
pnpm test

# Watch mode for test development
pnpm run watch-tests

# Run tests without compilation (if already compiled)
pnpm exec vscode-test
```

### Test Workflow

1. **Compile tests:** `pnpm run compile-tests`
   - TypeScript compiles `src/test/*.ts` → `out/test/*.js`

2. **Run tests:** `pnpm test`
   - Runs `pretest` (compile-tests + compile + lint)
   - Downloads VSCode if needed
   - Launches VSCode with extension loaded
   - Executes Mocha test suites
   - Reports results

### CI/CD Integration

GitHub Actions workflow for automated testing:

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: pnpm install --frozen-lockfile
      - run: xvfb-run -a pnpm test
        # xvfb required for headless VSCode on Linux
```

### Test Best Practices

1. **Isolate tests:** Each test should be independent
2. **Clean up:** Dispose of subscriptions and close panels after tests
3. **Async handling:** Use `async/await` for VSCode API calls
4. **Timeouts:** Set appropriate timeouts for slow operations (extension activation, process spawn)
5. **Fixtures:** Use `test-fixtures/` directory for sample Rails apps (for integration with konsol gem)

### Future: End-to-End Tests

For full integration testing with the konsol gem:

```
test-fixtures/
└── rails-app/           # Minimal Rails app with konsol gem
    ├── Gemfile
    ├── config/
    └── ...
```

**E2E test flow:**
1. Spawn konsol server from fixture app
2. Connect extension to server
3. Execute eval commands
4. Verify results match expected output
5. Clean up

---

## Build Configuration

### Build Script (`esbuild.js`)

Uses esbuild with dual configurations for extension host (Node.js) and webview (browser):

```javascript
const esbuild = require("esbuild");

const production = process.argv.includes("--production");
const watch = process.argv.includes("--watch");

// Plugin for VSCode problem matcher integration
const esbuildProblemMatcherPlugin = {
  name: "esbuild-problem-matcher",
  setup(build) {
    build.onStart(() => {
      console.log("[watch] build started");
    });
    build.onEnd((result) => {
      result.errors.forEach(({ text, location }) => {
        console.error(`✘ [ERROR] ${text}`);
        if (location) {
          console.error(`    ${location.file}:${location.line}:${location.column}:`);
        }
      });
      console.log("[watch] build finished");
    });
  },
};

// Extension host build (Node.js)
const extensionConfig = {
  entryPoints: ["src/extension.ts"],
  bundle: true,
  format: "cjs",
  minify: production,
  sourcemap: !production,
  sourcesContent: false,
  platform: "node",
  outfile: "dist/extension.js",
  external: ["vscode"],
  logLevel: "silent",
  plugins: [esbuildProblemMatcherPlugin],
};

// Webview build (Browser) - Phase 1c+
const webviewConfig = {
  entryPoints: ["webview/main.tsx"],
  bundle: true,
  format: "esm",
  minify: production,
  sourcemap: !production,
  sourcesContent: false,
  platform: "browser",
  outfile: "dist/webview/main.js",
  external: [],
  logLevel: "silent",
  plugins: [esbuildProblemMatcherPlugin],
  loader: {
    ".ttf": "file", // For Monaco editor fonts
    ".css": "css",
  },
  define: {
    "process.env.NODE_ENV": production ? '"production"' : '"development"',
  },
};

async function main() {
  const extensionCtx = await esbuild.context(extensionConfig);
  const webviewCtx = await esbuild.context(webviewConfig);

  if (watch) {
    await Promise.all([extensionCtx.watch(), webviewCtx.watch()]);
  } else {
    await Promise.all([extensionCtx.rebuild(), webviewCtx.rebuild()]);
    await Promise.all([extensionCtx.dispose(), webviewCtx.dispose()]);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
```

### Package.json Scripts

```json
{
  "scripts": {
    "vscode:prepublish": "pnpm run package",
    "compile": "pnpm run check-types && pnpm run lint && node esbuild.js",
    "watch": "npm-run-all -p watch:*",
    "watch:esbuild": "node esbuild.js --watch",
    "watch:tsc": "tsc --noEmit --watch --project tsconfig.json",
    "package": "pnpm run check-types && pnpm run lint && node esbuild.js --production",
    "compile-tests": "tsc -p . --outDir out",
    "watch-tests": "tsc -p . -w --outDir out",
    "pretest": "pnpm run compile-tests && pnpm run compile && pnpm run lint",
    "check-types": "tsc --noEmit",
    "lint": "eslint src",
    "test": "vscode-test"
  }
}
```

### TypeScript Configs

**tsconfig.json** (Extension Host):
```json
{
  "compilerOptions": {
    "module": "Node16",
    "target": "ES2022",
    "lib": ["ES2022"],
    "sourceMap": true,
    "rootDir": "src",
    "outDir": "out",

    "skipLibCheck": true,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedSideEffectImports": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "out"]
}
```

> **Note:** Do NOT add `noEmit: true` to this config. The `check-types` script already passes `--noEmit` explicitly, and `compile-tests` needs tsc to emit JS files for the VSCode test runner.

**tsconfig.webview.json** (React Webview - Phase 1c+):
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "jsx": "react-jsx",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["webview/**/*", "shared/**/*"],
  "exclude": ["node_modules"]
}
```

### Web Component Type Declarations (`webview/vscode-elements.d.ts`)

For React 19 to recognize vscode-elements:

```typescript
import type {
  VscodeButton,
  VscodeIcon,
  VscodeTextfield,
} from '@vscode-elements/elements'

type WebComponentProps<T> = Partial<T> & {
  class?: string
  children?: React.ReactNode
}

declare global {
  namespace JSX {
    interface IntrinsicElements {
      'vscode-button': WebComponentProps<VscodeButton> & {
        appearance?: 'primary' | 'secondary' | 'icon'
        disabled?: boolean
        onClick?: (e: Event) => void
      }
      'vscode-icon': WebComponentProps<VscodeIcon> & {
        name?: string
      }
      'vscode-textfield': WebComponentProps<VscodeTextfield> & {
        value?: string
        placeholder?: string
        onInput?: (e: Event) => void
      }
    }
  }
}

export {}
```

---

## Technical Considerations

### vscode-jsonrpc and LSP Framing

The `vscode-jsonrpc` library uses LSP-style `Content-Length` framing by default, which matches konsol's protocol exactly:

```typescript
import { StreamMessageReader, StreamMessageWriter } from 'vscode-jsonrpc/node'

// These use LSP framing automatically
const reader = new StreamMessageReader(process.stdout)
const writer = new StreamMessageWriter(process.stdin)
```

### Process Management

- Spawn konsol as child process of extension host
- Handle process crashes gracefully (show reconnect option)
- Kill process on extension deactivation
- Support workspace folder switching

### Webview Security

- Use strict CSP (Content Security Policy)
- Use nonces for inline scripts
- Use `asWebviewUri` for local resources
- Validate all messages between extension and webview

### Performance

- Debounce completion requests
- Lazy-load Monaco editor
- Virtual scroll for long output history
- Limit history size

---

## Dependencies Summary

### Extension Host (Node.js)
- `vscode-jsonrpc`: JSON-RPC 2.0 with LSP framing
- `zod`: Runtime validation and type inference
- `@types/vscode`: VSCode API types

### Webview (React 19)
- `react` + `react-dom`: UI framework (v19 for native web component support)
- `zustand`: Lightweight state management
- `zod`: Runtime validation and type inference (shared with extension)
- `ts-pattern`: Exhaustive pattern matching for message handling
- `@monaco-editor/react`: Monaco editor React wrapper
- `@vscode-elements/elements`: Native-looking UI components
- `@vscode/codicons`: VSCode icon font

### Build Tools
- `pnpm`: Fast package manager with efficient disk usage
- `typescript`: Type checking
- `esbuild`: Fast bundling for extension and webview

> **Note:** The `@vscode/webview-ui-toolkit` was deprecated Jan 2025. Use `@vscode-elements/elements` instead.
>
> **React 19 + Web Components:** No wrapper needed — use `<vscode-button>` directly in JSX.

---

## References

### Project Documentation
- [VSCODE_EXTENSION_BEST_PRACTICES.md](./VSCODE_EXTENSION_BEST_PRACTICES.md) — CSS variables, theming, security, performance
- [AUTOCOMPLETE_PLAN.md](./AUTOCOMPLETE_PLAN.md) — Autocomplete/Intellisense implementation strategy (future phase)

### VSCode Extension
- [VSCode Webview API](https://code.visualstudio.com/api/extension-guides/webview)
- [VSCode Theme Color Reference](https://code.visualstudio.com/api/references/theme-color)
- [VSCode Panel Guidelines](https://code.visualstudio.com/api/ux-guidelines/panel)
- [vscode-jsonrpc](https://www.npmjs.com/package/vscode-jsonrpc)

### React & State
- [React 19](https://react.dev/) — Native web component support
- [Zustand](https://zustand-demo.pmnd.rs/) — Lightweight state management
- [ts-pattern](https://github.com/gvergnaud/ts-pattern) — Exhaustive pattern matching
- [vscode-elements React Guide](https://vscode-elements.github.io/guides/framework-integrations/react/)

### Monaco Editor
- [Monaco Editor](https://microsoft.github.io/monaco-editor/)
- [@monaco-editor/react](https://github.com/suren-atoyan/monaco-react)
- [monaco-vscode-api](https://github.com/CodinGame/monaco-vscode-api) (advanced integration)

### UI Components
- [vscode-elements](https://vscode-elements.github.io/) — UI component library
- [@vscode/codicons](https://microsoft.github.io/vscode-codicons/)

### Ruby
- [Ruby LSP VSCode Extension](https://github.com/Shopify/vscode-ruby-lsp)

### Build Tools
- [esbuild](https://esbuild.github.io/) — Fast JavaScript/TypeScript bundler
- [pnpm](https://pnpm.io/) — Fast, disk-efficient package manager

---

## Open Questions

1. **Monaco bundle size** *(Resolved)*
   - `@monaco-editor/react` lazy-loads Monaco from CDN by default
   - **Problem:** Webview CSP blocks external scripts by default
   - **Decision:** Bundle Monaco locally (~2MB). Use `monaco-editor` directly with esbuild loader for `.ttf` fonts. This ensures CSP compliance and offline support.

2. **LSP Delegation complexity?**
   - Virtual document approach requires Ruby LSP to be active
   - May need fallback for projects without Ruby LSP
   - Consider making it optional enhancement

3. **Multi-root workspace support?**
   - Which Rails project to connect to?
   - Show project selector or use active editor's project

4. **Remote development (SSH, WSL, Containers)?**
   - Extension must spawn konsol on remote, not local
   - Use `vscode.env.remoteName` to detect
   - May need special handling for path resolution

5. **React 19 web component types?**
   - Need to add type declarations for `<vscode-button>` etc.
   - Create `vscode-elements.d.ts` with JSX.IntrinsicElements extensions
