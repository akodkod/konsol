# VSCode Extension Plan for Konsol

This document outlines the architecture and approach for building a VSCode extension that serves as a client for the Konsol gem — a JSON-RPC 2.0 Rails console backend.

---

## Overview

The extension provides a **custom terminal-like bottom panel** in VSCode for Rails projects. It features:

- **Code input** with Ruby autocomplete/intellisense (via Ruby LSP)
- **Output display** showing evaluation results, stdout, stderr, and exceptions
- **Session management** with persistent state across evaluations

---

## Architecture Options

### Option A: WebviewView Panel (Recommended)

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

**Pros:**
- Native VSCode integration (appears alongside Terminal, Problems, Output)
- Full HTML/CSS/JS flexibility for UI
- Can embed Monaco editor for code input
- Standard VSCode panel behavior (drag, resize, split)

**Cons:**
- Monaco in webview is isolated from main VSCode (no shared settings/themes)
- Requires custom autocomplete implementation

### Option B: Virtual Document + Output Channel

Use a virtual document for input and an output channel for results.

**Pros:**
- Native editor features (Ruby LSP works automatically)
- No webview overhead

**Cons:**
- Awkward UX (separate windows/panels)
- Less control over layout
- Not terminal-like experience

### Option C: Terminal with Custom Profile (Not Recommended)

Create a pseudo-terminal that wraps konsol.

**Cons:**
- Limited formatting options
- No rich UI elements
- Poor autocomplete integration

---

## Recommended Architecture: Option A with Monaco

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

### 4. Webview UI (`webview/index.html`, `webview/main.js`)

The webview contains:
- **Output area**: Scrollable history of commands and results
- **Monaco editor**: Single-line or multi-line code input
- **Status bar**: Connection status, session info

```html
<!DOCTYPE html>
<html>
<head>
  <style>
    .konsol-container { display: flex; flex-direction: column; height: 100%; }
    .output { flex: 1; overflow-y: auto; font-family: monospace; padding: 8px; }
    .input-area { border-top: 1px solid var(--vscode-panel-border); }
    .prompt { color: var(--vscode-terminal-ansiGreen); }
    .result { color: var(--vscode-terminal-ansiBrightBlue); }
    .error { color: var(--vscode-terminal-ansiRed); }
    .stdout { color: var(--vscode-terminal-foreground); }
  </style>
</head>
<body>
  <div class="konsol-container">
    <div class="output" id="output"></div>
    <div class="input-area">
      <div id="monaco-editor" style="height: 60px;"></div>
    </div>
  </div>
  <script src="${monacoLoaderUri}"></script>
  <script src="${mainScriptUri}"></script>
</body>
</html>
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
    "typescript": "^5.3.0",
    "esbuild": "^0.19.0"
  }
}
```

---

## Project Structure

```
vscode-konsol/
├── package.json
├── tsconfig.json
├── esbuild.config.js
├── src/
│   ├── extension.ts              # Entry point, activation
│   ├── konsol-client.ts          # JSON-RPC client for konsol
│   ├── konsol-view-provider.ts   # WebviewViewProvider
│   ├── completion-provider.ts    # LSP delegation / custom completions
│   ├── virtual-document.ts       # Virtual document for LSP bridging
│   └── types.ts                  # Shared type definitions
├── webview/
│   ├── index.html                # Webview HTML template
│   ├── main.ts                   # Webview entry point
│   ├── monaco-setup.ts           # Monaco editor configuration
│   ├── output-renderer.ts        # Render results/history
│   └── styles.css                # Webview styles
├── resources/
│   └── icons/
└── test/
    ├── extension.test.ts
    └── client.test.ts
```

---

## Implementation Phases

### Phase 1: Core Functionality (MVP)
1. Extension scaffolding with WebviewViewProvider
2. Basic HTML/CSS UI (no Monaco yet, use textarea)
3. Konsol client with JSON-RPC over stdio
4. Basic eval flow: input → konsol → output display
5. Session lifecycle (start/stop)

### Phase 2: Monaco Integration
1. Bundle Monaco editor for webview
2. Ruby syntax highlighting
3. Multi-line input support
4. Command history (up/down arrows)

### Phase 3: Autocomplete
1. Static Ruby/Rails completions
2. Session-aware completions (variables, methods)
3. LSP delegation for full intellisense (if Ruby LSP installed)

### Phase 4: Polish
1. Themes matching VSCode
2. Rich output formatting (syntax-highlighted results)
3. Error stack trace links (click to open file)
4. Inline object inspection
5. Keyboard shortcuts

### Phase 5: Advanced Features
1. Multiple sessions
2. Code snippets
3. History persistence
4. "Eval selection" from editor
5. Integration with Ruby debugger

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

## Alternative: Native Editor Approach

If webview complexity is a concern, consider a simpler approach:

### Using Output Channel + Input Box

```typescript
// Create output channel for results
const output = vscode.window.createOutputChannel('Konsol', 'ruby');

// Use input box for commands
vscode.commands.registerCommand('konsol.prompt', async () => {
  const code = await vscode.window.showInputBox({
    prompt: 'Enter Ruby code',
    placeHolder: 'User.count'
  });
  if (code) {
    const result = await client.eval(code);
    output.appendLine(`> ${code}`);
    output.appendLine(`=> ${result.value}`);
  }
});
```

**Pros:**
- Much simpler
- Native VSCode look and feel

**Cons:**
- Poor UX (modal input box)
- No persistent input area
- Limited formatting

---

## Dependencies Summary

### Extension Host (Node.js)
- `vscode-jsonrpc`: JSON-RPC 2.0 with LSP framing
- `@types/vscode`: VSCode API types

### Webview
- `monaco-editor`: Code editor (AMD bundle for browser)
- Or: Simple textarea for MVP

### Build Tools
- `typescript`: Type checking
- `esbuild`: Fast bundling for extension and webview

---

## References

- [VSCode Webview API](https://code.visualstudio.com/api/extension-guides/webview)
- [VSCode Panel Guidelines](https://code.visualstudio.com/api/ux-guidelines/panel)
- [vscode-jsonrpc](https://www.npmjs.com/package/vscode-jsonrpc)
- [Ruby LSP VSCode Extension](https://github.com/Shopify/vscode-ruby-lsp)
- [Monaco Editor](https://microsoft.github.io/monaco-editor/)
- [monaco-vscode-api](https://github.com/CodinGame/monaco-vscode-api) (advanced integration)

---

## Open Questions

1. **Monaco vs Textarea for MVP?**
   - Textarea is simpler but Monaco provides better UX
   - Recommendation: Start with textarea, add Monaco in Phase 2

2. **Bundling Monaco?**
   - Monaco is large (~2MB). Options:
     - Bundle in extension (larger extension size)
     - Load from CDN (requires network)
     - Use VSCode's built-in Monaco (complex, requires monaco-vscode-api)

3. **LSP Delegation complexity?**
   - Virtual document approach requires Ruby LSP to be active
   - May need fallback for projects without Ruby LSP
   - Consider making it optional enhancement

4. **Multi-root workspace support?**
   - Which Rails project to connect to?
   - Show project selector or use active editor's project

5. **Remote development (SSH, WSL, Containers)?**
   - Extension must spawn konsol on remote, not local
   - Use `vscode.env.remoteName` to detect
   - May need special handling for path resolution
