# VSCode Extension Best Practices

A comprehensive guide for building VSCode extensions with custom webview UI, focusing on native look and feel, theming, security, and performance.

---

## Table of Contents

1. [Native Theming with CSS Variables](#native-theming-with-css-variables)
2. [UI Component Libraries](#ui-component-libraries)
3. [Webview Security & CSP](#webview-security--csp)
4. [Message Passing](#message-passing)
5. [Performance & Activation](#performance--activation)
6. [Project Structure](#project-structure)

---

## Native Theming with CSS Variables

VSCode exposes **all theme colors as CSS variables** to webviews. Using these variables ensures your UI automatically adapts to any theme (light, dark, high contrast).

### Variable Naming Convention

Theme colors are converted to CSS variables with this pattern:
- Prefix: `--vscode-`
- Dots become dashes: `editor.foreground` → `--vscode-editor-foreground`

### Theme Detection via Body Classes

```css
/* Target specific theme types */
body.vscode-light {
  /* Light theme overrides */
}

body.vscode-dark {
  /* Dark theme overrides */
}

body.vscode-high-contrast {
  /* High contrast overrides - ALWAYS test this! */
}

/* Target a specific theme by ID */
body[data-vscode-theme-id="One Dark Pro"] {
  /* Theme-specific overrides */
}
```

### Essential Color Variables

#### Base Colors
```css
:root {
  /* Primary foreground/background */
  --vscode-foreground: /* Default foreground color */
  --vscode-disabledForeground: /* Foreground for disabled elements */
  --vscode-errorForeground: /* Error messages */
  --vscode-descriptionForeground: /* Description/secondary text */
  --vscode-focusBorder: /* Border color of focused elements */
}
```

#### Editor Colors
```css
:root {
  --vscode-editor-background: /* Editor background */
  --vscode-editor-foreground: /* Editor default foreground */
  --vscode-editorCursor-foreground: /* Cursor color */
  --vscode-editor-selectionBackground: /* Selection background */
  --vscode-editor-inactiveSelectionBackground: /* Inactive selection */
  --vscode-editor-lineHighlightBackground: /* Current line highlight */
}
```

#### Panel Colors (for bottom panel UI)
```css
:root {
  --vscode-panel-background: /* Panel background */
  --vscode-panel-border: /* Panel border */
  --vscode-panelTitle-activeBorder: /* Active tab indicator */
  --vscode-panelTitle-activeForeground: /* Active tab text */
  --vscode-panelTitle-inactiveForeground: /* Inactive tab text */
  --vscode-panelInput-border: /* Input border in panels */
  --vscode-panelSection-border: /* Section dividers */
  --vscode-panelSectionHeader-background: /* Section header background */
  --vscode-panelSectionHeader-foreground: /* Section header text */
}
```

#### Input Controls
```css
:root {
  --vscode-input-background: /* Input field background */
  --vscode-input-foreground: /* Input field text */
  --vscode-input-border: /* Input field border */
  --vscode-input-placeholderForeground: /* Placeholder text */
  --vscode-inputOption-activeBackground: /* Active option background */
  --vscode-inputOption-activeBorder: /* Active option border */
  --vscode-inputOption-activeForeground: /* Active option text */
  --vscode-inputValidation-errorBackground: /* Error state background */
  --vscode-inputValidation-errorBorder: /* Error state border */
  --vscode-inputValidation-warningBackground: /* Warning state background */
  --vscode-inputValidation-warningBorder: /* Warning state border */
}
```

#### Button Controls
```css
:root {
  --vscode-button-background: /* Primary button background */
  --vscode-button-foreground: /* Primary button text */
  --vscode-button-hoverBackground: /* Primary button hover */
  --vscode-button-secondaryBackground: /* Secondary button background */
  --vscode-button-secondaryForeground: /* Secondary button text */
  --vscode-button-secondaryHoverBackground: /* Secondary button hover */
  --vscode-button-border: /* Button border */
}
```

#### List & Tree Colors
```css
:root {
  --vscode-list-activeSelectionBackground: /* Selected item background */
  --vscode-list-activeSelectionForeground: /* Selected item text */
  --vscode-list-hoverBackground: /* Hover background */
  --vscode-list-hoverForeground: /* Hover text */
  --vscode-list-inactiveSelectionBackground: /* Inactive selection */
  --vscode-list-focusBackground: /* Focused item background */
  --vscode-list-focusForeground: /* Focused item text */
}
```

#### Scrollbar
```css
:root {
  --vscode-scrollbar-shadow: /* Scrollbar shadow */
  --vscode-scrollbarSlider-background: /* Scrollbar thumb */
  --vscode-scrollbarSlider-hoverBackground: /* Scrollbar thumb hover */
  --vscode-scrollbarSlider-activeBackground: /* Scrollbar thumb active */
}
```

#### Terminal Colors (useful for console-like UI)
```css
:root {
  --vscode-terminal-foreground: /* Terminal text */
  --vscode-terminal-background: /* Terminal background */
  --vscode-terminal-ansiBlack: /* ANSI black */
  --vscode-terminal-ansiRed: /* ANSI red */
  --vscode-terminal-ansiGreen: /* ANSI green */
  --vscode-terminal-ansiYellow: /* ANSI yellow */
  --vscode-terminal-ansiBlue: /* ANSI blue */
  --vscode-terminal-ansiMagenta: /* ANSI magenta */
  --vscode-terminal-ansiCyan: /* ANSI cyan */
  --vscode-terminal-ansiWhite: /* ANSI white */
  --vscode-terminal-ansiBrightBlack: /* ANSI bright black */
  --vscode-terminal-ansiBrightRed: /* ANSI bright red */
  --vscode-terminal-ansiBrightGreen: /* ANSI bright green */
  --vscode-terminal-ansiBrightYellow: /* ANSI bright yellow */
  --vscode-terminal-ansiBrightBlue: /* ANSI bright blue */
  --vscode-terminal-ansiBrightMagenta: /* ANSI bright magenta */
  --vscode-terminal-ansiBrightCyan: /* ANSI bright cyan */
  --vscode-terminal-ansiBrightWhite: /* ANSI bright white */
  --vscode-terminal-selectionBackground: /* Terminal selection */
}
```

#### Text Link Colors
```css
:root {
  --vscode-textLink-foreground: /* Link color */
  --vscode-textLink-activeForeground: /* Active/hover link */
  --vscode-textPreformat-foreground: /* Preformatted text */
  --vscode-textPreformat-background: /* Preformatted background */
  --vscode-textBlockQuote-background: /* Blockquote background */
  --vscode-textBlockQuote-border: /* Blockquote border */
  --vscode-textCodeBlock-background: /* Code block background */
}
```

#### Font Variables
```css
:root {
  --vscode-editor-font-family: /* Editor font (e.g., 'Fira Code') */
  --vscode-editor-font-size: /* Editor font size (e.g., '14px') */
  --vscode-editor-font-weight: /* Editor font weight */
  --vscode-font-family: /* UI font family */
  --vscode-font-size: /* UI font size */
  --vscode-font-weight: /* UI font weight */
}
```

### Best Practice: Always Use Fallbacks

```css
.my-element {
  /* Fallback for when CSS variable is unavailable */
  background: var(--vscode-input-background, #3c3c3c);
  color: var(--vscode-input-foreground, #cccccc);
  border: 1px solid var(--vscode-input-border, #3c3c3c);
}
```

### Example: Native-Looking Console UI

```css
/* Console container matching VSCode panel */
.konsol-container {
  background: var(--vscode-panel-background);
  color: var(--vscode-foreground);
  font-family: var(--vscode-editor-font-family), monospace;
  font-size: var(--vscode-editor-font-size);
  height: 100%;
  display: flex;
  flex-direction: column;
}

/* Output area like terminal */
.konsol-output {
  flex: 1;
  overflow-y: auto;
  padding: 8px 12px;
  background: var(--vscode-terminal-background, var(--vscode-panel-background));
}

/* Input area */
.konsol-input-wrapper {
  border-top: 1px solid var(--vscode-panel-border);
  padding: 8px;
  background: var(--vscode-input-background);
}

.konsol-input {
  width: 100%;
  background: var(--vscode-input-background);
  color: var(--vscode-input-foreground);
  border: 1px solid var(--vscode-input-border);
  padding: 4px 8px;
  font-family: var(--vscode-editor-font-family), monospace;
  font-size: var(--vscode-editor-font-size);
}

.konsol-input:focus {
  outline: none;
  border-color: var(--vscode-focusBorder);
}

/* Output formatting */
.konsol-prompt {
  color: var(--vscode-terminal-ansiGreen);
}

.konsol-result {
  color: var(--vscode-terminal-ansiBrightBlue);
}

.konsol-error {
  color: var(--vscode-terminal-ansiRed);
}

.konsol-stdout {
  color: var(--vscode-terminal-foreground);
}

.konsol-stderr {
  color: var(--vscode-terminal-ansiYellow);
}

/* Custom scrollbar matching VSCode */
.konsol-output::-webkit-scrollbar {
  width: 10px;
}

.konsol-output::-webkit-scrollbar-track {
  background: transparent;
}

.konsol-output::-webkit-scrollbar-thumb {
  background: var(--vscode-scrollbarSlider-background);
  border-radius: 5px;
}

.konsol-output::-webkit-scrollbar-thumb:hover {
  background: var(--vscode-scrollbarSlider-hoverBackground);
}
```

---

## UI Component Libraries

### vscode-elements (Recommended)

Since the official **@vscode/webview-ui-toolkit** was deprecated on January 1, 2025, use **vscode-elements** instead.

**Installation:**
```bash
npm install @vscode-elements/elements
```

**Documentation:** https://vscode-elements.github.io/

**Usage Example:**
```html
<script type="module">
  import '@vscode-elements/elements/dist/vscode-button/index.js';
  import '@vscode-elements/elements/dist/vscode-textfield/index.js';
</script>

<vscode-button>Run</vscode-button>
<vscode-textfield placeholder="Enter code..."></vscode-textfield>
```

**Available Components:**
- `vscode-button` - Primary and secondary buttons
- `vscode-textfield` - Text input fields
- `vscode-textarea` - Multi-line text areas
- `vscode-checkbox` - Checkboxes
- `vscode-radio` / `vscode-radio-group` - Radio buttons
- `vscode-dropdown` - Dropdown/select menus
- `vscode-table` - Data tables
- `vscode-tabs` / `vscode-tab-panel` - Tab navigation
- `vscode-tree` - Tree views
- `vscode-collapsible` - Collapsible sections
- `vscode-badge` - Status badges
- `vscode-icon` - Codicon icons
- `vscode-progress-ring` - Loading spinners

### Using Plain HTML with Native Styling

If you prefer not to use a component library, style native HTML elements with CSS variables:

```css
/* Native button styled like VSCode */
button.vscode-button {
  background: var(--vscode-button-background);
  color: var(--vscode-button-foreground);
  border: 1px solid var(--vscode-button-border, transparent);
  padding: 4px 14px;
  font-family: var(--vscode-font-family);
  font-size: var(--vscode-font-size);
  cursor: pointer;
  border-radius: 2px;
}

button.vscode-button:hover {
  background: var(--vscode-button-hoverBackground);
}

button.vscode-button:focus {
  outline: 1px solid var(--vscode-focusBorder);
  outline-offset: 2px;
}

button.vscode-button.secondary {
  background: var(--vscode-button-secondaryBackground);
  color: var(--vscode-button-secondaryForeground);
}

button.vscode-button.secondary:hover {
  background: var(--vscode-button-secondaryHoverBackground);
}

/* Native input styled like VSCode */
input.vscode-input,
textarea.vscode-textarea {
  background: var(--vscode-input-background);
  color: var(--vscode-input-foreground);
  border: 1px solid var(--vscode-input-border);
  padding: 4px 8px;
  font-family: var(--vscode-font-family);
  font-size: var(--vscode-font-size);
}

input.vscode-input:focus,
textarea.vscode-textarea:focus {
  outline: none;
  border-color: var(--vscode-focusBorder);
}

input.vscode-input::placeholder,
textarea.vscode-textarea::placeholder {
  color: var(--vscode-input-placeholderForeground);
}
```

### Using Codicons (VSCode Icons)

VSCode provides the Codicon icon font. Load it in your webview:

```typescript
// In extension
const codiconsUri = webview.asWebviewUri(
  vscode.Uri.joinPath(context.extensionUri, 'node_modules', '@vscode/codicons', 'dist', 'codicon.css')
);
```

```html
<link rel="stylesheet" href="${codiconsUri}">

<!-- Use icons -->
<span class="codicon codicon-play"></span>
<span class="codicon codicon-debug-stop"></span>
<span class="codicon codicon-trash"></span>
```

**Installation:**
```bash
npm install @vscode/codicons
```

---

## Webview Security & CSP

### Content Security Policy (Required)

Always include a strict CSP in your webview HTML:

```typescript
function getWebviewContent(webview: vscode.Webview, extensionUri: vscode.Uri): string {
  // Generate nonce for inline scripts
  const nonce = getNonce();

  // Get URIs for local resources
  const styleUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'webview', 'styles.css')
  );
  const scriptUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'webview', 'main.js')
  );

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="
    default-src 'none';
    style-src ${webview.cspSource} 'unsafe-inline';
    script-src 'nonce-${nonce}';
    font-src ${webview.cspSource};
    img-src ${webview.cspSource} https: data:;
  ">
  <link rel="stylesheet" href="${styleUri}">
  <title>Konsol</title>
</head>
<body>
  <div id="app"></div>
  <script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
}

function getNonce(): string {
  let text = '';
  const possible = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 32; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length));
  }
  return text;
}
```

### CSP Directives Explained

| Directive | Recommended Value | Purpose |
|-----------|-------------------|---------|
| `default-src` | `'none'` | Block everything by default |
| `script-src` | `'nonce-${nonce}'` | Only allow scripts with nonce |
| `style-src` | `${webview.cspSource} 'unsafe-inline'` | Allow extension styles + inline |
| `font-src` | `${webview.cspSource}` | Allow extension fonts (codicons) |
| `img-src` | `${webview.cspSource} https: data:` | Allow extension images, https, data URIs |
| `connect-src` | `'none'` or specific URLs | Control fetch/XHR destinations |

### Local Resource Roots

Restrict which files the webview can access:

```typescript
webview.options = {
  enableScripts: true,
  localResourceRoots: [
    vscode.Uri.joinPath(extensionUri, 'webview'),
    vscode.Uri.joinPath(extensionUri, 'node_modules', '@vscode')
  ]
};
```

### Security Checklist

- [ ] Use strict CSP with nonces for scripts
- [ ] Set `localResourceRoots` to minimum required paths
- [ ] Validate all messages received from webview
- [ ] Never use `eval()` or `innerHTML` with untrusted content
- [ ] Sanitize any user input before display
- [ ] Use `vscode.env.asExternalUri` for external links
- [ ] Store secrets using `context.secrets` API, not in webview

---

## Message Passing

### Extension → Webview

```typescript
// Extension side
webview.postMessage({
  type: 'evalResult',
  data: {
    value: '42',
    stdout: '',
    stderr: ''
  }
});
```

```javascript
// Webview side
window.addEventListener('message', (event) => {
  const message = event.data;
  switch (message.type) {
    case 'evalResult':
      displayResult(message.data);
      break;
  }
});
```

### Webview → Extension

```javascript
// Webview side - acquire API once, reuse everywhere
const vscode = acquireVsCodeApi();

function sendCode(code) {
  vscode.postMessage({
    type: 'eval',
    code: code
  });
}
```

```typescript
// Extension side
webview.onDidReceiveMessage(
  async (message) => {
    switch (message.type) {
      case 'eval':
        const result = await client.eval(message.code);
        webview.postMessage({ type: 'evalResult', data: result });
        break;
    }
  },
  undefined,
  context.subscriptions
);
```

### Type-Safe Message Passing

Define shared message types:

```typescript
// types.ts (shared between extension and webview)
export type WebviewMessage =
  | { type: 'eval'; code: string }
  | { type: 'requestCompletions'; code: string; position: number }
  | { type: 'clear' };

export type ExtensionMessage =
  | { type: 'evalResult'; data: EvalResult }
  | { type: 'completions'; data: CompletionItem[] }
  | { type: 'status'; connected: boolean };

export interface EvalResult {
  value: string;
  valueType?: string;
  stdout: string;
  stderr: string;
  exception?: {
    class: string;
    message: string;
    backtrace: string[];
  };
}
```

### Request/Response Pattern with Promises

For async operations, use a request ID pattern:

```typescript
// Webview side
const pendingRequests = new Map<string, { resolve: Function; reject: Function }>();

function request<T>(type: string, params: any): Promise<T> {
  const id = crypto.randomUUID();
  return new Promise((resolve, reject) => {
    pendingRequests.set(id, { resolve, reject });
    vscode.postMessage({ type, id, ...params });

    // Timeout after 30 seconds
    setTimeout(() => {
      if (pendingRequests.has(id)) {
        pendingRequests.delete(id);
        reject(new Error('Request timeout'));
      }
    }, 30000);
  });
}

window.addEventListener('message', (event) => {
  const { type, id, data, error } = event.data;

  if (id && pendingRequests.has(id)) {
    const { resolve, reject } = pendingRequests.get(id)!;
    pendingRequests.delete(id);

    if (error) {
      reject(new Error(error));
    } else {
      resolve(data);
    }
  }
});

// Usage
const result = await request<EvalResult>('eval', { code: 'User.count' });
```

### State Persistence

Use the webview state API to persist UI state across visibility changes:

```javascript
// Webview side
const vscode = acquireVsCodeApi();

// Restore state on load
const previousState = vscode.getState() || { history: [], scrollPosition: 0 };
restoreUI(previousState);

// Save state on change
function saveState() {
  vscode.setState({
    history: commandHistory,
    scrollPosition: outputElement.scrollTop
  });
}
```

---

## Performance & Activation

### Activation Events

Choose the most specific activation events:

```json
{
  "activationEvents": [
    "workspaceContains:**/Gemfile",
    "onView:konsol.panel",
    "onCommand:konsol.start"
  ]
}
```

| Event | Use Case |
|-------|----------|
| `onLanguage:ruby` | Language-specific features |
| `onCommand:*` | Explicit user action |
| `onView:*` | When view becomes visible |
| `workspaceContains:**/pattern` | Project type detection |
| `onStartupFinished` | Non-critical startup tasks |
| `*` | **AVOID** - impacts all users |

### Lazy Loading in Activation

```typescript
export async function activate(context: vscode.ExtensionContext) {
  // Register commands immediately (cheap)
  context.subscriptions.push(
    vscode.commands.registerCommand('konsol.start', () => {
      // Lazy load heavy dependencies only when needed
      const { KonsolClient } = require('./konsol-client');
      return new KonsolClient().start();
    })
  );

  // Register view provider (cheap, webview loads lazily)
  const provider = new KonsolViewProvider(context.extensionUri);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider('konsol.panel', provider)
  );

  // DON'T do heavy work here:
  // - Don't spawn child processes
  // - Don't read large files
  // - Don't make network requests
}
```

### Webview Performance

```typescript
// Retain webview context to avoid reloading
vscode.window.registerWebviewViewProvider('konsol.panel', provider, {
  webviewOptions: {
    retainContextWhenHidden: true  // Keep webview alive when hidden
  }
});
```

```javascript
// Webview: Virtual scroll for long output
class VirtualScroller {
  constructor(container, itemHeight, renderItem) {
    this.container = container;
    this.itemHeight = itemHeight;
    this.renderItem = renderItem;
    this.items = [];

    container.addEventListener('scroll', () => this.render());
  }

  render() {
    const scrollTop = this.container.scrollTop;
    const height = this.container.clientHeight;

    const startIndex = Math.floor(scrollTop / this.itemHeight);
    const endIndex = Math.min(
      startIndex + Math.ceil(height / this.itemHeight) + 1,
      this.items.length
    );

    // Only render visible items
    const fragment = document.createDocumentFragment();
    for (let i = startIndex; i < endIndex; i++) {
      const el = this.renderItem(this.items[i], i);
      el.style.position = 'absolute';
      el.style.top = `${i * this.itemHeight}px`;
      fragment.appendChild(el);
    }

    this.container.innerHTML = '';
    this.container.appendChild(fragment);
  }
}
```

### Debounce Expensive Operations

```javascript
// Webview: Debounce completion requests
function debounce(fn, delay) {
  let timeoutId;
  return (...args) => {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
}

const requestCompletions = debounce((code, position) => {
  vscode.postMessage({ type: 'requestCompletions', code, position });
}, 150);

// Call on every keystroke - only fires after 150ms pause
editor.onDidChangeModelContent(() => {
  requestCompletions(editor.getValue(), editor.getPosition());
});
```

### Bundle Size Optimization

Use esbuild for fast, small bundles:

```javascript
// esbuild.config.js
const esbuild = require('esbuild');

// Extension bundle
esbuild.build({
  entryPoints: ['src/extension.ts'],
  bundle: true,
  outfile: 'out/extension.js',
  external: ['vscode'],
  format: 'cjs',
  platform: 'node',
  minify: true,
  sourcemap: true
});

// Webview bundle
esbuild.build({
  entryPoints: ['webview/main.ts'],
  bundle: true,
  outfile: 'out/webview.js',
  format: 'iife',
  platform: 'browser',
  minify: true,
  sourcemap: true
});
```

---

## Project Structure

### Recommended Layout

```
vscode-konsol/
├── package.json              # Extension manifest
├── tsconfig.json             # TypeScript config
├── esbuild.config.js         # Build configuration
├── .vscodeignore             # Files to exclude from package
├── CHANGELOG.md
├── README.md
│
├── src/                      # Extension source (Node.js)
│   ├── extension.ts          # Entry point, activation
│   ├── konsol-client.ts      # JSON-RPC client
│   ├── konsol-view-provider.ts
│   ├── completion-provider.ts
│   └── types.ts              # Shared types
│
├── webview/                  # Webview source (Browser)
│   ├── index.html            # HTML template
│   ├── main.ts               # Webview entry point
│   ├── styles.css            # Styles using CSS variables
│   ├── components/           # UI components
│   │   ├── output.ts
│   │   └── input.ts
│   └── lib/
│       └── vscode-api.ts     # VSCode API wrapper
│
├── resources/                # Static assets
│   ├── icons/
│   │   ├── konsol.svg
│   │   ├── konsol-dark.svg
│   │   └── konsol-light.svg
│   └── snippets/
│
├── test/                     # Tests
│   ├── extension.test.ts
│   └── client.test.ts
│
└── out/                      # Compiled output (gitignored)
    ├── extension.js
    └── webview.js
```

### package.json Essentials

```json
{
  "name": "vscode-konsol",
  "displayName": "Konsol",
  "description": "Rails console for VSCode",
  "version": "0.1.0",
  "publisher": "your-publisher-id",
  "repository": {
    "type": "git",
    "url": "https://github.com/you/vscode-konsol"
  },
  "engines": {
    "vscode": "^1.85.0"
  },
  "categories": ["Other"],
  "keywords": ["rails", "ruby", "console", "repl"],

  "activationEvents": [
    "workspaceContains:**/Gemfile"
  ],

  "main": "./out/extension.js",

  "contributes": {
    "viewsContainers": {
      "panel": [{
        "id": "konsol",
        "title": "Konsol",
        "icon": "$(terminal)"
      }]
    },
    "views": {
      "konsol": [{
        "type": "webview",
        "id": "konsol.panel",
        "name": "Rails Console"
      }]
    },
    "commands": [{
      "command": "konsol.start",
      "title": "Start Session",
      "category": "Konsol",
      "icon": "$(play)"
    }],
    "configuration": {
      "title": "Konsol",
      "properties": {
        "konsol.railsEnv": {
          "type": "string",
          "default": "development",
          "description": "Rails environment"
        }
      }
    }
  },

  "scripts": {
    "vscode:prepublish": "npm run build",
    "build": "node esbuild.config.js",
    "watch": "node esbuild.config.js --watch",
    "test": "vscode-test",
    "package": "vsce package",
    "publish": "vsce publish"
  },

  "devDependencies": {
    "@types/vscode": "^1.85.0",
    "@vscode/test-electron": "^2.3.0",
    "@vscode/vsce": "^2.22.0",
    "esbuild": "^0.19.0",
    "typescript": "^5.3.0"
  },

  "dependencies": {
    "vscode-jsonrpc": "^8.2.0"
  }
}
```

### .vscodeignore

```
.vscode/**
src/**
webview/**/*.ts
test/**
node_modules/**
.gitignore
tsconfig.json
esbuild.config.js
**/*.map
```

---

## References

- [VSCode Webview API](https://code.visualstudio.com/api/extension-guides/webview)
- [Theme Color Reference](https://code.visualstudio.com/api/references/theme-color)
- [Activation Events](https://code.visualstudio.com/api/references/activation-events)
- [vscode-elements](https://vscode-elements.github.io/)
- [Extension Security](https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security)
- [Codicons](https://microsoft.github.io/vscode-codicons/dist/codicon.html)

---

## Checklist for Native Look & Feel

- [ ] Use `--vscode-*` CSS variables for all colors
- [ ] Test in light, dark, AND high contrast themes
- [ ] Use `--vscode-font-family` and `--vscode-editor-font-family`
- [ ] Match VSCode spacing (4px, 8px, 12px increments)
- [ ] Use codicons for icons
- [ ] Style scrollbars with `--vscode-scrollbarSlider-*`
- [ ] Match panel borders with `--vscode-panel-border`
- [ ] Use vscode-elements or custom styled native elements
- [ ] Ensure keyboard navigation works (Tab, Enter, Escape)
- [ ] Support screen readers with proper ARIA labels
