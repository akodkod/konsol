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

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Package Manager** | npm | Industry standard, best vsce compatibility |
| **Extension Host** | TypeScript | VSCode extension runtime (Node.js) |
| **Webview UI** | React 19 | Component-based UI with native web component support |
| **State Management** | Zustand | Lightweight global store for webview state |
| **Schema Validation** | Zod | Runtime validation + TypeScript type inference |
| **Code Editor** | Monaco + @monaco-editor/react | Rich code input with syntax highlighting |
| **UI Components** | vscode-elements | Native VSCode look via web components |
| **Communication** | vscode-jsonrpc | JSON-RPC 2.0 with LSP framing |
| **Build Tool** | esbuild | Fast bundling for extension and webview |

### Why These Choices

- **React 19**: Native web component support — use `<vscode-button>` directly without wrappers
- **Zustand**: Minimal boilerplate, works great with React, easy persistence via `getState()`/`setState()`
- **Zod**: Runtime validation of JSON-RPC messages with automatic TypeScript type inference via `z.infer<>`
- **npm**: Best compatibility with vsce (VSCode Extension CLI) for packaging and publishing

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
│  │  │  │  (History)      │  │  - Ruby syntax highlighting  │   │  │  │
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
  const provider = new KonsolViewProvider(context.extensionUri);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider('konsol.panel', provider, {
      webviewOptions: { retainContextWhenHidden: true }
    })
  );

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('konsol.start', () => provider.start()),
    vscode.commands.registerCommand('konsol.stop', () => provider.stop()),
    vscode.commands.registerCommand('konsol.clear', () => provider.clear())
  );
}
```

### 2. Konsol Client (`konsol-client.ts`)

Uses `vscode-jsonrpc` for JSON-RPC communication over stdio:

```typescript
import * as cp from 'child_process';
import * as rpc from 'vscode-jsonrpc/node';

class KonsolClient {
  private process: cp.ChildProcess | null = null;
  private connection: rpc.MessageConnection | null = null;
  private sessionId: string | null = null;

  async start(workspaceRoot: string): Promise<void> {
    // Spawn konsol process
    this.process = cp.spawn('bundle', ['exec', 'konsol', '--stdio'], {
      cwd: workspaceRoot,
      env: { ...process.env, RAILS_ENV: 'development' }
    });

    // Create JSON-RPC connection with LSP-style framing
    this.connection = rpc.createMessageConnection(
      new rpc.StreamMessageReader(this.process.stdout!),
      new rpc.StreamMessageWriter(this.process.stdin!)
    );

    this.connection.listen();

    // Initialize
    await this.connection.sendRequest('initialize', {
      clientInfo: { name: 'vscode-konsol', version: '0.1.0' }
    });

    // Create session
    const result = await this.connection.sendRequest('konsol/session.create', {});
    this.sessionId = result.sessionId;
  }

  async eval(code: string): Promise<EvalResult> {
    return this.connection!.sendRequest('konsol/eval', {
      sessionId: this.sessionId,
      code
    });
  }

  async shutdown(): Promise<void> {
    await this.connection?.sendRequest('shutdown');
    this.connection?.sendNotification('exit');
    this.process?.kill();
  }
}
```

### 3. WebviewViewProvider (`konsol-view-provider.ts`)

Manages the webview panel lifecycle and communication:

```typescript
class KonsolViewProvider implements vscode.WebviewViewProvider {
  private view?: vscode.WebviewView;
  private client?: KonsolClient;

  resolveWebviewView(webviewView: vscode.WebviewView) {
    this.view = webviewView;

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri]
    };

    webviewView.webview.html = this.getHtmlContent();

    // Handle messages from webview
    webviewView.webview.onDidReceiveMessage(async (message) => {
      switch (message.type) {
        case 'eval':
          const result = await this.client?.eval(message.code);
          this.view?.webview.postMessage({ type: 'result', data: result });
          break;
        case 'requestCompletion':
          const completions = await this.getCompletions(message.code, message.position);
          this.view?.webview.postMessage({ type: 'completions', data: completions });
          break;
      }
    });
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

```typescript
import { create } from 'zustand';
import type { EvalResult } from '../../shared/types';

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface OutputEntry {
  id: string;
  type: 'command' | 'result' | 'error' | 'stdout' | 'stderr';
  code?: string;
  result?: EvalResult;
  chunk?: string;  // For stdout/stderr streaming
  timestamp: number;
}

interface KonsolState {
  // Connection
  connected: boolean;
  sessionId: string | null;

  // UI State
  history: OutputEntry[];
  commandHistory: string[];
  historyIndex: number;
  isEvaluating: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// Store (private — NOT exported)
// ─────────────────────────────────────────────────────────────────────────────

const store = create<KonsolState>()(() => ({
  connected: false,
  sessionId: null,
  history: [],
  commandHistory: [],
  historyIndex: -1,
  isEvaluating: false,
}));

// ─────────────────────────────────────────────────────────────────────────────
// Selectors (exported hooks)
// ─────────────────────────────────────────────────────────────────────────────

export const useConnected = () => store((s) => s.connected);
export const useSessionId = () => store((s) => s.sessionId);
export const useHistory = () => store((s) => s.history);
export const useCommandHistory = () => store((s) => s.commandHistory);
export const useHistoryIndex = () => store((s) => s.historyIndex);
export const useIsEvaluating = () => store((s) => s.isEvaluating);

// ─────────────────────────────────────────────────────────────────────────────
// Mutators (exported actions)
// ─────────────────────────────────────────────────────────────────────────────

export const setConnected = (connected: boolean, sessionId?: string) => {
  store.setState({ connected, sessionId: sessionId ?? null });
};

export const addEntry = (entry: Omit<OutputEntry, 'id' | 'timestamp'>) => {
  store.setState((state) => ({
    history: [
      ...state.history,
      { ...entry, id: crypto.randomUUID(), timestamp: Date.now() },
    ],
    commandHistory:
      entry.type === 'command' && entry.code
        ? [...state.commandHistory, entry.code]
        : state.commandHistory,
    historyIndex: -1,
  }));
};

export const clearHistory = () => {
  store.setState({ history: [], historyIndex: -1 });
};

export const setEvaluating = (isEvaluating: boolean) => {
  store.setState({ isEvaluating });
};

export const navigateHistory = (direction: 'up' | 'down'): string | null => {
  const { commandHistory, historyIndex } = store.getState();
  if (commandHistory.length === 0) return null;

  let newIndex: number;
  if (direction === 'up') {
    newIndex = historyIndex === -1
      ? commandHistory.length - 1
      : Math.max(0, historyIndex - 1);
  } else {
    newIndex = historyIndex === -1
      ? -1
      : Math.min(commandHistory.length - 1, historyIndex + 1);
  }

  store.setState({ historyIndex: newIndex });
  return newIndex >= 0 ? commandHistory[newIndex] : null;
};
```

**Benefits of this pattern:**
- Store internals are encapsulated — no direct access to `set()` or `get()`
- Components only import what they need: `useHistory()`, `addEntry()`, etc.
- Mutators can be used outside React components (e.g., in message handlers)
- Easier to test — mock individual functions instead of the whole store
- Clear separation: hooks for reading, functions for writing

#### React Entry (`webview/main.tsx`)

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import './styles/konsol.css';

// Import vscode-elements (React 19 native web component support)
import '@vscode-elements/elements/dist/vscode-button';
import '@vscode-elements/elements/dist/vscode-icon';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
```

#### App Component (`webview/App.tsx`)

```tsx
import { useEffect } from 'react';
import { Output } from './components/Output';
import { Editor } from './components/Editor';
import { StatusBar } from './components/StatusBar';
import { setConnected, addEntry, setEvaluating } from './stores/konsol-store';
import { vscode } from './lib/vscode-api';
import { parseExtensionMessage, ExtensionMessageType } from '../../shared/events';

export function App() {
  useEffect(() => {
    // Listen for messages from extension host
    const handleMessage = (event: MessageEvent<unknown>) => {
      // Validate message with Zod schema
      const result = parseExtensionMessage(event.data);
      if (!result.success) {
        console.error('Invalid message from extension:', result.error);
        return;
      }

      const message = result.data;

      switch (message.type) {
        case ExtensionMessageType.Connected:
          setConnected(true, message.sessionId);
          break;

        case ExtensionMessageType.Disconnected:
          setConnected(false);
          break;

        case ExtensionMessageType.EvalResult:
          setEvaluating(false);
          if (message.data.exception) {
            addEntry({ type: 'error', result: message.data });
          } else {
            addEntry({ type: 'result', result: message.data });
          }
          break;

        case ExtensionMessageType.Stdout:
          addEntry({ type: 'stdout', chunk: message.data.chunk });
          break;

        case ExtensionMessageType.Stderr:
          addEntry({ type: 'stderr', chunk: message.data.chunk });
          break;

        case ExtensionMessageType.Status:
          setEvaluating(message.data.busy);
          break;

        case ExtensionMessageType.Error:
          setEvaluating(false);
          addEntry({
            type: 'error',
            result: {
              value: '',
              stdout: '',
              stderr: '',
              exception: {
                className: 'RpcError',
                message: `[${message.error.code}] ${message.error.message}`,
                backtrace: [],
              },
            },
          });
          break;
      }
    };

    window.addEventListener('message', handleMessage);

    // Notify extension we're ready
    vscode.postMessage({ type: 'ready' });

    return () => window.removeEventListener('message', handleMessage);
  }, []); // No dependencies — mutators are stable module-level functions

  const handleEval = (code: string) => {
    if (!code.trim()) return;

    addEntry({ type: 'command', code });
    setEvaluating(true);
    vscode.postMessage({ type: 'eval', code });
  };

  return (
    <div className="konsol-container">
      <Output />
      <Editor onEval={handleEval} />
      <StatusBar />
    </div>
  );
}
```

#### Editor Component with Monaco (`webview/components/Editor.tsx`)

```tsx
import { useRef, useCallback } from 'react';
import MonacoEditor, { type OnMount } from '@monaco-editor/react';
import { useIsEvaluating, navigateHistory } from '../stores/konsol-store';

interface EditorProps {
  onEval: (code: string) => void;
}

export function Editor({ onEval }: EditorProps) {
  const editorRef = useRef<any>(null);
  const isEvaluating = useIsEvaluating();

  const handleMount: OnMount = (editor, monaco) => {
    editorRef.current = editor;

    // Ctrl/Cmd+Enter to evaluate
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, () => {
      const code = editor.getValue();
      onEval(code);
      editor.setValue('');
    });

    // Up arrow for history
    editor.addCommand(monaco.KeyCode.UpArrow, () => {
      const prev = navigateHistory('up');
      if (prev !== null) editor.setValue(prev);
    });

    // Down arrow for history
    editor.addCommand(monaco.KeyCode.DownArrow, () => {
      const next = navigateHistory('down');
      if (next !== null) editor.setValue(next);
    });

    editor.focus();
  };

  const handleRun = useCallback(() => {
    if (editorRef.current) {
      const code = editorRef.current.getValue();
      onEval(code);
      editorRef.current.setValue('');
    }
  }, [onEval]);

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
  );
}
```

#### Output Component (`webview/components/Output.tsx`)

```tsx
import { useEffect, useRef } from 'react';
import { useHistory } from '../stores/konsol-store';
import { OutputEntry } from './OutputEntry';

export function Output() {
  const history = useHistory();
  const bottomRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom on new entries
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [history]);

  return (
    <div className="konsol-output">
      {history.map((entry) => (
        <OutputEntry key={entry.id} entry={entry} />
      ))}
      <div ref={bottomRef} />
    </div>
  );
}
```

#### VSCode API Wrapper (`webview/lib/vscode-api.ts`)

```typescript
interface VSCodeAPI {
  postMessage: (message: unknown) => void;
  getState: () => unknown;
  setState: (state: unknown) => void;
}

// Acquire once, reuse everywhere
export const vscode: VSCodeAPI = acquireVsCodeApi();
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

Types are split into two files:
- `shared/types.ts` — TypeScript types matching the konsol gem's Sorbet structs
- `shared/events.ts` — Zod schemas for runtime validation with inferred types

All JSON keys use **camelCase** (converted from Ruby's snake_case at protocol boundary).

#### JSON-RPC Method Names (`shared/types.ts`)

```typescript
/**
 * JSON-RPC method names - must match Konsol::Protocol::Method enum
 */
export enum KonsolMethod {
  // Lifecycle
  Initialize = 'initialize',
  Shutdown = 'shutdown',
  Exit = 'exit',
  CancelRequest = '$/cancelRequest',

  // Console
  SessionCreate = 'konsol/session.create',
  Eval = 'konsol/eval',
  Interrupt = 'konsol/interrupt',

  // Notifications (server → client)
  Stdout = 'konsol/stdout',
  Stderr = 'konsol/stderr',
  Status = 'konsol/status',
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
```

#### Request Parameter Types

```typescript
/**
 * Initialize request params
 * @see Konsol::Protocol::Requests::InitializeParams
 */
export interface ClientInfo {
  name: string;
  version?: string;
}

export interface InitializeParams {
  processId?: number;
  clientInfo?: ClientInfo;
}

/**
 * Session create request params (empty)
 * @see Konsol::Protocol::Requests::SessionCreateParams
 */
export interface SessionCreateParams {}

/**
 * Eval request params
 * @see Konsol::Protocol::Requests::EvalParams
 */
export interface EvalParams {
  sessionId: string;
  code: string;
}

/**
 * Interrupt request params
 * @see Konsol::Protocol::Requests::InterruptParams
 */
export interface InterruptParams {
  sessionId: string;
}

/**
 * Cancel request params
 * @see Konsol::Protocol::Requests::CancelParams
 */
export interface CancelParams {
  id: string | number;
}
```

#### Response Result Types

```typescript
/**
 * Initialize response result
 * @see Konsol::Protocol::Responses::InitializeResult
 */
export interface ServerInfo {
  name: string;
  version: string;
}

export interface Capabilities {
  supportsInterrupt: boolean;
}

export interface InitializeResult {
  serverInfo: ServerInfo;
  capabilities: Capabilities;
}

/**
 * Session create response result
 * @see Konsol::Protocol::Responses::SessionCreateResult
 */
export interface SessionCreateResult {
  sessionId: string;
}

/**
 * Exception info within eval result
 * @see Konsol::Protocol::Responses::ExceptionInfo
 */
export interface ExceptionInfo {
  className: string;
  message: string;
  backtrace: string[];
}

/**
 * Eval response result
 * @see Konsol::Protocol::Responses::EvalResult
 */
export interface EvalResult {
  value: string;
  valueType?: string;
  stdout: string;
  stderr: string;
  exception?: ExceptionInfo;
}

/**
 * Interrupt response result
 * @see Konsol::Protocol::Responses::InterruptResult
 */
export interface InterruptResult {
  success: boolean;
}
```

#### Notification Parameter Types

```typescript
/**
 * Stdout notification params
 * @see Konsol::Protocol::Notifications::StdoutParams
 */
export interface StdoutParams {
  sessionId: string;
  chunk: string;
}

/**
 * Stderr notification params
 * @see Konsol::Protocol::Notifications::StderrParams
 */
export interface StderrParams {
  sessionId: string;
  chunk: string;
}

/**
 * Status notification params
 * @see Konsol::Protocol::Notifications::StatusParams
 */
export interface StatusParams {
  sessionId: string;
  busy: boolean;
}
```

#### JSON-RPC Message Types

```typescript
/**
 * JSON-RPC error data
 * @see Konsol::Protocol::Message::ErrorData
 */
export interface RpcError {
  code: ErrorCodeType;
  message: string;
  data?: Record<string, unknown>;
}

/**
 * JSON-RPC request
 */
export interface RpcRequest<P = unknown> {
  jsonrpc: '2.0';
  id: string | number | null;
  method: string;
  params?: P;
}

/**
 * JSON-RPC response
 */
export interface RpcResponse<R = unknown> {
  jsonrpc: '2.0';
  id: string | number | null;
  result?: R;
  error?: RpcError;
}

/**
 * JSON-RPC notification (no id, no response expected)
 */
export interface RpcNotification<P = unknown> {
  jsonrpc: '2.0';
  method: string;
  params?: P;
}
```

#### Extension ↔ Webview Message Types (`shared/types.ts`)

```typescript
/**
 * Message types for extension → webview communication
 */
export enum ExtensionMessageType {
  Connected = 'connected',
  Disconnected = 'disconnected',
  EvalResult = 'evalResult',
  Stdout = 'stdout',
  Stderr = 'stderr',
  Status = 'status',
  Error = 'error',
}

/**
 * Message types for webview → extension communication
 */
export enum WebviewMessageType {
  Ready = 'ready',
  Eval = 'eval',
  Interrupt = 'interrupt',
  Clear = 'clear',
  RequestCompletions = 'requestCompletions',
}
```

#### Zod Schemas for Event Validation (`shared/events.ts`)

Zod schemas provide runtime validation and automatic TypeScript type inference via `z.infer<>`.

```typescript
import { z } from 'zod';
import { ExtensionMessageType, WebviewMessageType, ErrorCode } from './types';

// ─────────────────────────────────────────────────────────────────────────────
// Shared Schemas
// ─────────────────────────────────────────────────────────────────────────────

const ExceptionInfoSchema = z.object({
  className: z.string(),
  message: z.string(),
  backtrace: z.array(z.string()),
});

const EvalResultSchema = z.object({
  value: z.string(),
  valueType: z.string().optional(),
  stdout: z.string(),
  stderr: z.string(),
  exception: ExceptionInfoSchema.optional(),
});

const StdoutParamsSchema = z.object({
  sessionId: z.string(),
  chunk: z.string(),
});

const StderrParamsSchema = z.object({
  sessionId: z.string(),
  chunk: z.string(),
});

const StatusParamsSchema = z.object({
  sessionId: z.string(),
  busy: z.boolean(),
});

const RpcErrorSchema = z.object({
  code: z.nativeEnum(ErrorCode),
  message: z.string(),
  data: z.record(z.unknown()).optional(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Extension → Webview Messages
// ─────────────────────────────────────────────────────────────────────────────

const ConnectedMessageSchema = z.object({
  type: z.literal(ExtensionMessageType.Connected),
  sessionId: z.string(),
});

const DisconnectedMessageSchema = z.object({
  type: z.literal(ExtensionMessageType.Disconnected),
  reason: z.string().optional(),
});

const EvalResultMessageSchema = z.object({
  type: z.literal(ExtensionMessageType.EvalResult),
  data: EvalResultSchema,
});

const StdoutMessageSchema = z.object({
  type: z.literal(ExtensionMessageType.Stdout),
  data: StdoutParamsSchema,
});

const StderrMessageSchema = z.object({
  type: z.literal(ExtensionMessageType.Stderr),
  data: StderrParamsSchema,
});

const StatusMessageSchema = z.object({
  type: z.literal(ExtensionMessageType.Status),
  data: StatusParamsSchema,
});

const ErrorMessageSchema = z.object({
  type: z.literal(ExtensionMessageType.Error),
  error: RpcErrorSchema,
});

export const ExtensionMessageSchema = z.discriminatedUnion('type', [
  ConnectedMessageSchema,
  DisconnectedMessageSchema,
  EvalResultMessageSchema,
  StdoutMessageSchema,
  StderrMessageSchema,
  StatusMessageSchema,
  ErrorMessageSchema,
]);

// ─────────────────────────────────────────────────────────────────────────────
// Webview → Extension Messages
// ─────────────────────────────────────────────────────────────────────────────

const ReadyMessageSchema = z.object({
  type: z.literal(WebviewMessageType.Ready),
});

const EvalMessageSchema = z.object({
  type: z.literal(WebviewMessageType.Eval),
  code: z.string(),
});

const InterruptMessageSchema = z.object({
  type: z.literal(WebviewMessageType.Interrupt),
});

const ClearMessageSchema = z.object({
  type: z.literal(WebviewMessageType.Clear),
});

const RequestCompletionsMessageSchema = z.object({
  type: z.literal(WebviewMessageType.RequestCompletions),
  code: z.string(),
  position: z.number(),
});

export const WebviewMessageSchema = z.discriminatedUnion('type', [
  ReadyMessageSchema,
  EvalMessageSchema,
  InterruptMessageSchema,
  ClearMessageSchema,
  RequestCompletionsMessageSchema,
]);

// ─────────────────────────────────────────────────────────────────────────────
// Inferred Types (use these instead of manual type definitions)
// ─────────────────────────────────────────────────────────────────────────────

export type ExtensionMessage = z.infer<typeof ExtensionMessageSchema>;
export type WebviewMessage = z.infer<typeof WebviewMessageSchema>;
export type EvalResult = z.infer<typeof EvalResultSchema>;
export type ExceptionInfo = z.infer<typeof ExceptionInfoSchema>;
export type RpcError = z.infer<typeof RpcErrorSchema>;

// ─────────────────────────────────────────────────────────────────────────────
// Validation Helpers
// ─────────────────────────────────────────────────────────────────────────────

export const parseExtensionMessage = (data: unknown) =>
  ExtensionMessageSchema.safeParse(data);

export const parseWebviewMessage = (data: unknown) =>
  WebviewMessageSchema.safeParse(data);

// Re-export enums for convenience
export { ExtensionMessageType, WebviewMessageType } from './types';
```

**Benefits of Zod schemas:**
- Runtime validation of messages from webview/extension boundary
- Types are inferred from schemas — single source of truth
- `safeParse()` returns discriminated result with typed errors
- `z.discriminatedUnion()` enables exhaustive switch statements
- Schemas can be composed and reused

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
├── package-lock.json             # npm lockfile (use npm, not pnpm/bun)
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
│   │   ├── Output.tsx            # Command history display
│   │   ├── OutputEntry.tsx       # Single output entry (prompt, result, error)
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
│   ├── types.ts                  # Enums, interfaces (no runtime code)
│   └── schemas.ts                # Zod schemas + z.infer<> types + validators
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
1. Project scaffolding with npm, TypeScript, esbuild
2. Extension host with WebviewViewProvider (static HTML)
3. Konsol process spawn with JSON-RPC connection
4. `initialize` handshake validation
5. Basic error handling for missing konsol gem

### Phase 1b: Basic Eval Flow
1. Simple webview UI with vanilla HTML/JS (no React yet)
2. `<textarea>` input + Run button
3. Single eval roundtrip: input → konsol → output display
4. Session create/destroy lifecycle
5. stdout/stderr streaming display

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

| Tool | Purpose |
|------|---------|
| `@vscode/test-cli` | CLI runner for VSCode extension tests |
| `@vscode/test-electron` | Downloads and launches VSCode for testing |
| `Mocha` | Test framework (suite/test pattern) |
| `assert` | Node.js built-in assertions |

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
import * as assert from 'assert';
import * as vscode from 'vscode';

suite('Extension Test Suite', () => {
  vscode.window.showInformationMessage('Start all tests.');

  test('Extension should be present', () => {
    assert.ok(vscode.extensions.getExtension('konsol.konsol'));
  });

  test('Extension should activate', async () => {
    const ext = vscode.extensions.getExtension('konsol.konsol');
    await ext?.activate();
    assert.strictEqual(ext?.isActive, true);
  });

  test('Commands should be registered', async () => {
    const commands = await vscode.commands.getCommands(true);
    assert.ok(commands.includes('konsol.start'));
    assert.ok(commands.includes('konsol.stop'));
    assert.ok(commands.includes('konsol.clear'));
  });
});
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
import { describe, it } from 'mocha';
import * as assert from 'assert';
import { parseExtensionMessage } from '../../shared/schemas';

describe('Message Parsing', () => {
  it('should parse valid connected message', () => {
    const result = parseExtensionMessage({
      type: 'connected',
      sessionId: 'abc-123'
    });
    assert.ok(result.success);
  });

  it('should reject invalid message', () => {
    const result = parseExtensionMessage({
      type: 'invalid'
    });
    assert.ok(!result.success);
  });
});
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
import { defineConfig } from '@vscode/test-cli';

export default defineConfig({
  files: 'out/test/**/*.test.js',
  // Optionally specify VSCode version
  // version: 'stable',
  // workspaceFolder: './test-fixtures/workspace',
  // extensionDevelopmentPath: '.',
});
```

#### Running Tests

```bash
# Run all tests (compiles first)
npm test

# Watch mode for test development
npm run watch-tests

# Run tests without compilation (if already compiled)
npx vscode-test
```

### Test Workflow

1. **Compile tests:** `npm run compile-tests`
   - TypeScript compiles `src/test/*.ts` → `out/test/*.js`

2. **Run tests:** `npm test`
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
      - run: npm ci
      - run: xvfb-run -a npm test
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
    "vscode:prepublish": "npm run package",
    "compile": "npm run check-types && npm run lint && node esbuild.js",
    "watch": "npm-run-all -p watch:*",
    "watch:esbuild": "node esbuild.js --watch",
    "watch:tsc": "tsc --noEmit --watch --project tsconfig.json",
    "package": "npm run check-types && npm run lint && node esbuild.js --production",
    "compile-tests": "tsc -p . --outDir out",
    "watch-tests": "tsc -p . -w --outDir out",
    "pretest": "npm run compile-tests && npm run compile && npm run lint",
    "check-types": "tsc --noEmit",
    "lint": "eslint src",
    "test": "vscode-test"
  }
}
```

**Note:** Use `npm` as the package manager for best vsce compatibility. The scripts already use `npm run` commands.

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
} from '@vscode-elements/elements';

type WebComponentProps<T> = Partial<T> & {
  class?: string;
  children?: React.ReactNode;
};

declare global {
  namespace JSX {
    interface IntrinsicElements {
      'vscode-button': WebComponentProps<VscodeButton> & {
        appearance?: 'primary' | 'secondary' | 'icon';
        disabled?: boolean;
        onClick?: (e: Event) => void;
      };
      'vscode-icon': WebComponentProps<VscodeIcon> & {
        name?: string;
      };
      'vscode-textfield': WebComponentProps<VscodeTextfield> & {
        value?: string;
        placeholder?: string;
        onInput?: (e: Event) => void;
      };
    }
  }
}

export {};
```

---

## Technical Considerations

### vscode-jsonrpc and LSP Framing

The `vscode-jsonrpc` library uses LSP-style `Content-Length` framing by default, which matches konsol's protocol exactly:

```typescript
import { StreamMessageReader, StreamMessageWriter } from 'vscode-jsonrpc/node';

// These use LSP framing automatically
const reader = new StreamMessageReader(process.stdout);
const writer = new StreamMessageWriter(process.stdin);
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
- `@monaco-editor/react`: Monaco editor React wrapper
- `@vscode-elements/elements`: Native-looking UI components
- `@vscode/codicons`: VSCode icon font

### Build Tools
- `npm`: Package manager (best vsce compatibility)
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
- [npm](https://docs.npmjs.com/) — Node.js package manager

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
