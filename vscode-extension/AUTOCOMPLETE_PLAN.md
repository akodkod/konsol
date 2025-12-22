# Autocomplete / Intellisense Strategy

> **Note:** This feature is planned for a future phase, not the MVP. See [VSCODE_EXTENSION_PLAN.md](./VSCODE_EXTENSION_PLAN.md) for the main implementation plan.

---

## Challenge

Monaco editor inside a webview is **isolated** from VSCode's language services. Ruby LSP completions don't automatically work.

---

## Solutions (in order of recommendation)

### Solution 1: Extension-Side LSP Delegation (Recommended)

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

---

### Solution 2: Custom Completion Provider

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

---

### Solution 3: Monaco-VSCode-API (Advanced)

Use [@codingame/monaco-vscode-api](https://github.com/CodinGame/monaco-vscode-api) to bridge Monaco with VSCode services.

**Pros:**
- Full VSCode API compatibility in webview
- Themes, settings, keybindings all work

**Cons:**
- Complex setup
- Large bundle size
- May have compatibility issues

---

## Recommended Hybrid Approach

1. **Primary**: LSP Delegation for full Ruby intellisense
2. **Fallback**: Static completions when LSP unavailable
3. **Enhancement**: Session-aware completions (local variables, etc.)

---

## Implementation Steps

### Step 1: Static Completions (Basic)

Provide Ruby/Rails keywords and common methods without any external dependencies.

```typescript
const RUBY_KEYWORDS = [
  'def', 'end', 'class', 'module', 'if', 'else', 'elsif', 'unless',
  'case', 'when', 'while', 'until', 'for', 'do', 'begin', 'rescue',
  'ensure', 'raise', 'return', 'yield', 'self', 'super', 'nil',
  'true', 'false', 'and', 'or', 'not', 'in', 'then', 'attr_reader',
  'attr_writer', 'attr_accessor', 'private', 'protected', 'public',
];

const RAILS_METHODS = [
  'belongs_to', 'has_many', 'has_one', 'validates', 'before_action',
  'after_action', 'scope', 'where', 'find', 'find_by', 'create',
  'update', 'destroy', 'save', 'new', 'all', 'first', 'last',
  'order', 'limit', 'offset', 'includes', 'joins', 'group',
];
```

### Step 2: Session-Aware Completions

Query the konsol session for available methods and variables:

```typescript
// Get local variables
const locals = await this.client.eval('local_variables.map(&:to_s)');

// Get instance variables
const ivars = await this.client.eval('instance_variables.map(&:to_s)');

// Get methods on a specific object
const methods = await this.client.eval('User.methods(false).map(&:to_s)');
```

### Step 3: LSP Delegation

Full Ruby LSP integration via virtual documents:

```typescript
class VirtualDocumentProvider implements vscode.TextDocumentContentProvider {
  private documents = new Map<string, string>();

  provideTextDocumentContent(uri: vscode.Uri): string {
    return this.documents.get(uri.toString()) || '';
  }

  updateDocument(sessionId: string, content: string): vscode.Uri {
    const uri = vscode.Uri.parse(`konsol-virtual://session/${sessionId}.rb`);
    this.documents.set(uri.toString(), content);
    this._onDidChange.fire(uri);
    return uri;
  }
}
```

---

## Files to Create

```
src/
├── completion/
│   ├── completion-provider.ts    # Main completion orchestrator
│   ├── static-completions.ts     # Ruby/Rails keyword completions
│   ├── session-completions.ts    # Dynamic session-based completions
│   └── virtual-document.ts       # LSP delegation via virtual docs
```

---

## References

- [Monaco Editor Completion API](https://microsoft.github.io/monaco-editor/api/interfaces/languages.CompletionItemProvider.html)
- [VSCode TextDocumentContentProvider](https://code.visualstudio.com/api/extension-guides/virtual-documents)
- [Ruby LSP](https://github.com/Shopify/ruby-lsp)
- [monaco-vscode-api](https://github.com/CodinGame/monaco-vscode-api)
