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
| **Package Manager** | Bun | Fast installs, builds, and scripts |
| **Extension Host** | TypeScript | VSCode extension runtime (Node.js) |
| **Webview UI** | React 19 | Component-based UI with native web component support |
| **State Management** | Zustand | Lightweight global store for webview state |
| **Code Editor** | Monaco + @monaco-editor/react | Rich code input with syntax highlighting |
| **UI Components** | vscode-elements | Native VSCode look via web components |
| **Communication** | vscode-jsonrpc | JSON-RPC 2.0 with LSP framing |
| **Build Tool** | esbuild (via Bun) | Fast bundling for extension and webview |

### Why These Choices

- **React 19**: Native web component support — use `<vscode-button>` directly without wrappers
- **Zustand**: Minimal boilerplate, works great with React, easy persistence via `getState()`/`setState()`
- **Bun**: Faster than npm/yarn, built-in TypeScript support, simpler scripts

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
// - workspaceContains:**/Gemfile (contains 'konsol' or 'rails')
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

```typescript
import { create } from 'zustand';
import type { EvalResult, StdoutParams, StderrParams } from '../../shared/types';

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

  // Actions
  setConnected: (connected: boolean, sessionId?: string) => void;
  addEntry: (entry: Omit<OutputEntry, 'id' | 'timestamp'>) => void;
  clearHistory: () => void;
  setEvaluating: (isEvaluating: boolean) => void;
  navigateHistory: (direction: 'up' | 'down') => string | null;
}

export const useKonsolStore = create<KonsolState>((set, get) => ({
  // Initial state
  connected: false,
  sessionId: null,
  history: [],
  commandHistory: [],
  historyIndex: -1,
  isEvaluating: false,

  // Actions
  setConnected: (connected, sessionId) =>
    set({ connected, sessionId: sessionId ?? null }),

  addEntry: (entry) =>
    set((state) => ({
      history: [
        ...state.history,
        { ...entry, id: crypto.randomUUID(), timestamp: Date.now() },
      ],
      commandHistory:
        entry.type === 'command' && entry.code
          ? [...state.commandHistory, entry.code]
          : state.commandHistory,
      historyIndex: -1,
    })),

  clearHistory: () => set({ history: [], historyIndex: -1 }),

  setEvaluating: (isEvaluating) => set({ isEvaluating }),

  navigateHistory: (direction) => {
    const { commandHistory, historyIndex } = get();
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

    set({ historyIndex: newIndex });
    return newIndex >= 0 ? commandHistory[newIndex] : null;
  },
}));
```

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
import { useKonsolStore } from './stores/konsol-store';
import { vscode } from './lib/vscode-api';
import type { ExtensionMessage } from '../../shared/types';

export function App() {
  const { setConnected, addEntry, setEvaluating } = useKonsolStore();

  useEffect(() => {
    // Listen for messages from extension host
    const handleMessage = (event: MessageEvent<ExtensionMessage>) => {
      const message = event.data;

      switch (message.type) {
        case 'connected':
          setConnected(true, message.sessionId);
          break;

        case 'disconnected':
          setConnected(false);
          break;

        case 'evalResult':
          setEvaluating(false);
          // Check if result has exception
          if (message.data.exception) {
            addEntry({ type: 'error', result: message.data });
          } else {
            addEntry({ type: 'result', result: message.data });
          }
          break;

        case 'stdout':
          // Streaming stdout from konsol/stdout notification
          addEntry({ type: 'stdout', chunk: message.data.chunk });
          break;

        case 'stderr':
          // Streaming stderr from konsol/stderr notification
          addEntry({ type: 'stderr', chunk: message.data.chunk });
          break;

        case 'status':
          // Session busy status from konsol/status notification
          setEvaluating(message.data.busy);
          break;

        case 'error':
          // JSON-RPC error
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
  }, [setConnected, addEntry, setEvaluating]);

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
import { useKonsolStore } from '../stores/konsol-store';

interface EditorProps {
  onEval: (code: string) => void;
}

export function Editor({ onEval }: EditorProps) {
  const editorRef = useRef<any>(null);
  const { isEvaluating, navigateHistory } = useKonsolStore();

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
import { useKonsolStore } from '../stores/konsol-store';
import { OutputEntry } from './OutputEntry';

export function Output() {
  const { history } = useKonsolStore();
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

### 5. Shared Protocol Types (`shared/types.ts`)

TypeScript types matching the konsol gem's Sorbet structs. All JSON keys use **camelCase** (converted from Ruby's snake_case at protocol boundary).

#### JSON-RPC Method Names

```typescript
/**
 * JSON-RPC method names - must match Konsol::Protocol::Method enum
 */
export const KonsolMethod = {
  // Lifecycle
  Initialize: 'initialize',
  Shutdown: 'shutdown',
  Exit: 'exit',
  CancelRequest: '$/cancelRequest',

  // Console
  SessionCreate: 'konsol/session.create',
  Eval: 'konsol/eval',
  Interrupt: 'konsol/interrupt',

  // Notifications (server → client)
  Stdout: 'konsol/stdout',
  Stderr: 'konsol/stderr',
  Status: 'konsol/status',
} as const;

export type KonsolMethodType = (typeof KonsolMethod)[keyof typeof KonsolMethod];
```

#### Error Codes

```typescript
/**
 * JSON-RPC error codes - must match Konsol::Protocol::ErrorCode enum
 */
export const ErrorCode = {
  // Standard JSON-RPC
  ParseError: -32700,
  InvalidRequest: -32600,
  MethodNotFound: -32601,
  InvalidParams: -32602,
  InternalError: -32603,

  // Konsol-specific
  SessionNotFound: -32001,
  SessionBusy: -32002,
  RailsBootFailed: -32003,
  EvalTimeout: -32004,
  ServerShuttingDown: -32005,
} as const;

export type ErrorCodeType = (typeof ErrorCode)[keyof typeof ErrorCode];
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

#### Extension ↔ Webview Messages

```typescript
/**
 * Messages from extension host to webview
 */
export type ExtensionMessage =
  | { type: 'connected'; sessionId: string }
  | { type: 'disconnected'; reason?: string }
  | { type: 'evalResult'; data: EvalResult }
  | { type: 'stdout'; data: StdoutParams }
  | { type: 'stderr'; data: StderrParams }
  | { type: 'status'; data: StatusParams }
  | { type: 'error'; error: RpcError };

/**
 * Messages from webview to extension host
 */
export type WebviewMessage =
  | { type: 'ready' }
  | { type: 'eval'; code: string }
  | { type: 'interrupt' }
  | { type: 'clear' }
  | { type: 'requestCompletions'; code: string; position: number };
```

---

## Autocomplete / Intellisense Strategy

### Challenge

Monaco editor inside a webview is **isolated** from VSCode's language services. Ruby LSP completions don't automatically work.

### Solutions (in order of recommendation)

#### Solution 1: Extension-Side LSP Delegation (Recommended)

The extension host acts as a bridge between Monaco and Ruby LSP:

```
Monaco (webview) → postMessage → Extension Host → Ruby LSP → back to Monaco
```

**Implementation:**

```typescript
// In extension host
async getCompletions(code: string, position: Position): Promise<CompletionItem[]> {
  // Create a virtual document with the code
  const virtualUri = vscode.Uri.parse(`konsol-virtual://session/${Date.now()}.rb`);

  // Use VSCode's completion API which delegates to Ruby LSP
  const completions = await vscode.commands.executeCommand<vscode.CompletionList>(
    'vscode.executeCompletionItemProvider',
    virtualUri,
    position
  );

  return completions.items.map(item => ({
    label: item.label,
    kind: item.kind,
    detail: item.detail,
    insertText: item.insertText
  }));
}
```

**Requirements:**
- Register a `TextDocumentContentProvider` for `konsol-virtual://` scheme
- Keep virtual document content in sync with Monaco editor content
- Map Monaco positions to VSCode positions

#### Solution 2: Custom Completion Provider

Build a custom Ruby completion provider using:

1. **Static completions**: Rails/Ruby keywords, common methods
2. **Dynamic completions**: Query konsol for available methods/variables

```typescript
// Query session for available completions
async getSessionCompletions(prefix: string): Promise<string[]> {
  // Eval a completion helper in the session
  const result = await this.client.eval(`
    methods.grep(/^${prefix}/).take(50)
  `);
  return JSON.parse(result.value);
}
```

**Pros:**
- Works without Ruby LSP
- Can include session-specific variables

**Cons:**
- Less comprehensive than Ruby LSP
- Requires careful implementation

#### Solution 3: Monaco-VSCode-API (Advanced)

Use [@codingame/monaco-vscode-api](https://github.com/CodinGame/monaco-vscode-api) to bridge Monaco with VSCode services.

**Pros:**
- Full VSCode API compatibility in webview
- Themes, settings, keybindings all work

**Cons:**
- Complex setup
- Large bundle size
- May have compatibility issues

### Recommended Hybrid Approach

1. **Primary**: LSP Delegation for full Ruby intellisense
2. **Fallback**: Static completions when LSP unavailable
3. **Enhancement**: Session-aware completions (local variables, etc.)

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
    "workspaceContains:**/Gemfile"
  ],
  "main": "./out/extension.js",
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
    "vscode-jsonrpc": "^8.2.0"
  },
  "devDependencies": {
    "@types/vscode": "^1.85.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "typescript": "^5.3.0"
  },
  "webviewDependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "zustand": "^5.0.0",
    "@monaco-editor/react": "^4.6.0",
    "@vscode-elements/elements": "^1.6.0",
    "@vscode/codicons": "^0.0.36"
  }
}
```

---

## Project Structure

```
vscode-konsol/
├── package.json
├── tsconfig.json
├── tsconfig.webview.json         # Separate config for React webview
├── bun.lock
├── build.ts                      # Bun build script
│
├── src/                          # Extension Host (Node.js)
│   ├── extension.ts              # Entry point, activation
│   ├── konsol-client.ts          # JSON-RPC client for konsol
│   ├── konsol-view-provider.ts   # WebviewViewProvider
│   ├── completion-provider.ts    # LSP delegation / custom completions
│   ├── virtual-document.ts       # Virtual document for LSP bridging
│   └── types.ts                  # Shared type definitions
│
├── webview/                      # React 19 Webview (Browser)
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
│   │   ├── konsol-store.ts       # Zustand store for session state
│   │   └── types.ts              # Store types
│   ├── hooks/
│   │   ├── use-vscode-api.ts     # VSCode API hook
│   │   └── use-konsol.ts         # Konsol actions hook
│   ├── lib/
│   │   └── vscode-api.ts         # acquireVsCodeApi wrapper
│   └── styles/
│       └── konsol.css            # Styles using VSCode CSS variables
│
├── shared/                       # Shared between extension and webview
│   └── types.ts                  # Message types, EvalResult, etc.
│
├── resources/
│   └── icons/
│
└── test/
    ├── extension.test.ts
    └── webview.test.tsx
```

---

## Implementation Phases

### Phase 1: Core Functionality (MVP)
1. Project scaffolding with Bun, React 19, TypeScript
2. Extension host with WebviewViewProvider
3. React webview with basic UI (Output + simple textarea input)
4. Zustand store for state management
5. Konsol client with JSON-RPC over stdio
6. Basic eval flow: input → konsol → output display
7. Session lifecycle (start/stop/reconnect)

### Phase 2: Monaco Integration
1. Replace textarea with `@monaco-editor/react`
2. Ruby syntax highlighting
3. Multi-line input support
4. Command history (up/down arrows)
5. Keyboard shortcuts (Ctrl+Enter to run)

### Phase 3: Autocomplete
1. Static Ruby/Rails completions
2. Session-aware completions (variables, methods)
3. LSP delegation for full intellisense (if Ruby LSP installed)

### Phase 4: Polish
1. Native theming with VSCode CSS variables
2. Rich output formatting (syntax-highlighted results)
3. Error stack trace links (click to open file)
4. Inline object inspection
5. Loading states and error handling

### Phase 5: Advanced Features
1. Multiple sessions (tabs)
2. Code snippets
3. History persistence (via `vscode.setState`)
4. "Eval selection" from editor (context menu)
5. Integration with Ruby debugger

---

## Build Configuration

### Build Script (`build.ts`)

Uses Bun's built-in bundler (powered by esbuild) for fast builds:

```typescript
import type { BuildConfig } from 'bun';

const isDev = process.argv.includes('--watch');
const isWatch = process.argv.includes('--watch');

// Extension Host (Node.js / CommonJS)
const extensionConfig: BuildConfig = {
  entrypoints: ['./src/extension.ts'],
  outdir: './out',
  target: 'node',
  format: 'cjs',
  external: ['vscode'],
  sourcemap: isDev ? 'inline' : 'none',
  minify: !isDev,
  naming: '[name].js',
};

// Webview (Browser / ESM)
const webviewConfig: BuildConfig = {
  entrypoints: ['./webview/main.tsx'],
  outdir: './out/webview',
  target: 'browser',
  format: 'esm',
  sourcemap: isDev ? 'inline' : 'none',
  minify: !isDev,
  naming: '[name].js',
};

async function build() {
  console.log(`🔨 Building${isWatch ? ' (watch mode)' : ''}...`);

  const results = await Promise.all([
    Bun.build(extensionConfig),
    Bun.build(webviewConfig),
  ]);

  const [ext, web] = results;

  if (!ext.success || !web.success) {
    console.error('❌ Build failed');
    for (const result of results) {
      for (const log of result.logs) {
        console.error(log);
      }
    }
    process.exit(1);
  }

  console.log(`✅ Extension: ${ext.outputs.length} file(s)`);
  console.log(`✅ Webview: ${web.outputs.length} file(s)`);
}

build();
```

### Package.json Scripts

```json
{
  "scripts": {
    "build": "bun run build.ts",
    "watch": "bun run build.ts --watch",
    "dev": "bun run watch",
    "typecheck": "tsc --noEmit",
    "lint": "eslint src webview --ext .ts,.tsx",
    "package": "bun run build && vsce package --no-dependencies",
    "publish": "bun run build && vsce publish --no-dependencies"
  }
}
```

### TypeScript Configs

**tsconfig.json** (Extension Host):
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "CommonJS",
    "lib": ["ES2022"],
    "outDir": "./out",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*", "shared/**/*"],
  "exclude": ["node_modules", "webview"]
}
```

**tsconfig.webview.json** (React Webview):
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
- `@types/vscode`: VSCode API types

### Webview (React 19)
- `react` + `react-dom`: UI framework (v19 for native web component support)
- `zustand`: Lightweight state management
- `@monaco-editor/react`: Monaco editor React wrapper
- `@vscode-elements/elements`: Native-looking UI components
- `@vscode/codicons`: VSCode icon font

### Build Tools
- `bun`: Package manager and build runner
- `typescript`: Type checking
- `esbuild`: Fast bundling (via Bun)

> **Note:** The `@vscode/webview-ui-toolkit` was deprecated Jan 2025. Use `@vscode-elements/elements` instead.
>
> **React 19 + Web Components:** No wrapper needed — use `<vscode-button>` directly in JSX.

---

## References

### Project Documentation
- [VSCODE_EXTENSION_BEST_PRACTICES.md](./VSCODE_EXTENSION_BEST_PRACTICES.md) — CSS variables, theming, security, performance

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
- [Bun](https://bun.sh/) — Package manager and runtime

---

## Open Questions

1. **Monaco bundle size**
   - `@monaco-editor/react` lazy-loads Monaco from CDN by default
   - Alternative: Bundle locally for offline support (adds ~2MB)
   - Decision: Use CDN for now, reconsider if offline needed

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
