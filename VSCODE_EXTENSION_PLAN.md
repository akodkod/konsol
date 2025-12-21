# VSCode Extension Plan for Konsol

This document outlines the architecture and approach for building a VSCode extension that serves as a client for the Konsol gem — a JSON-RPC 2.0 Rails console backend.

---

## Overview

The extension provides a **custom terminal-like bottom panel** in VSCode for Rails projects. It features:

- **Code input** with Ruby autocomplete/intellisense (via Ruby LSP)
- **Output display** showing evaluation results, stdout, stderr, and exceptions
- **Session management** with persistent state across evaluations

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

### 4. Webview UI (`webview/index.html`, `webview/main.js`)

The webview contains:
- **Output area**: Scrollable history of commands and results
- **Monaco editor**: Single-line or multi-line code input
- **Status bar**: Connection status, session info

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
  <div class="konsol-container">
    <div class="konsol-output" id="output"></div>
    <div class="konsol-input-wrapper">
      <div id="monaco-editor"></div>
      <button class="konsol-run-btn" title="Run (Ctrl+Enter)">
        <span class="codicon codicon-play"></span>
      </button>
    </div>
  </div>
  <script nonce="${nonce}" src="${mainScriptUri}"></script>
</body>
</html>
```

**Styling with VSCode CSS variables** (see `VSCODE_EXTENSION_BEST_PRACTICES.md` for full reference):

```css
/* Uses native VSCode theme colors */
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
  border-top: 1px solid var(--vscode-panel-border);
  background: var(--vscode-input-background);
}

/* Terminal-style output colors */
.konsol-prompt  { color: var(--vscode-terminal-ansiGreen); }
.konsol-result  { color: var(--vscode-terminal-ansiBrightBlue); }
.konsol-error   { color: var(--vscode-terminal-ansiRed); }
.konsol-stdout  { color: var(--vscode-terminal-foreground); }
.konsol-stderr  { color: var(--vscode-terminal-ansiYellow); }
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
    "vscode-jsonrpc": "^8.2.0",
    "@vscode-elements/elements": "^1.0.0",
    "@vscode/codicons": "^0.0.36"
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

## Dependencies Summary

### Extension Host (Node.js)
- `vscode-jsonrpc`: JSON-RPC 2.0 with LSP framing
- `@types/vscode`: VSCode API types

### Webview
- `monaco-editor`: Code editor (AMD bundle for browser)
- `@vscode-elements/elements`: Native-looking UI components (buttons, inputs, etc.)
- `@vscode/codicons`: VSCode icon font

### Build Tools
- `typescript`: Type checking
- `esbuild`: Fast bundling for extension and webview

> **Note:** The `@vscode/webview-ui-toolkit` was deprecated Jan 2025. Use `@vscode-elements/elements` instead.

---

## References

- [VSCODE_EXTENSION_BEST_PRACTICES.md](./VSCODE_EXTENSION_BEST_PRACTICES.md) — CSS variables, theming, security, performance
- [VSCode Webview API](https://code.visualstudio.com/api/extension-guides/webview)
- [VSCode Theme Color Reference](https://code.visualstudio.com/api/references/theme-color)
- [VSCode Panel Guidelines](https://code.visualstudio.com/api/ux-guidelines/panel)
- [vscode-elements](https://vscode-elements.github.io/) — UI component library
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
