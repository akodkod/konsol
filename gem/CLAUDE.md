# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Konsol is a two-part project:
1. **Gem** (`/gem`): A Ruby JSON-RPC 2.0 Rails console server with Sorbet type checking
2. **VSCode Extension** (`/vscode-extension`): A TypeScript VSCode extension client (in development)

The gem provides a GUI-friendly Rails console backend using LSP-style framing (`Content-Length: <bytes>\r\n\r\n<JSON>`) over stdio.

## Commands

### Gem (Ruby)

```bash
cd gem

# Run tests (default rake task runs spec + rubocop)
bundle exec rake

# Run RSpec tests only
bundle exec rspec

# Run a single test file
bundle exec rspec spec/unit/framing/reader_spec.rb

# Linting
bundle exec rubocop
bundle exec rubocop -A  # Auto-correct

# Type checking is handled by Sorbet at runtime
# Sorbet checks lib/ and exe/, excludes spec/
```

### VSCode Extension (TypeScript)

```bash
cd vscode-extension

# Install dependencies
npm install

# Build (type check + lint + esbuild)
npm run compile

# Watch mode
npm run watch

# Type check only
npm run check-types

# Lint
npm run lint

# Run tests
npm run test
```

## Architecture

### Gem Server Flow

1. **CLI Entry** (`exe/konsol`): Parses `--stdio` flag, starts server
2. **Server Loop** (`lib/konsol/server.rb`): Reads JSON-RPC messages via framing protocol
3. **Message Dispatch**: Routes to handlers (Lifecycle or Konsol)
4. **Session Management**:
   - Boots Rails via `config/environment.rb` on first session
   - Creates isolated session bindings that persist state between evals
5. **Evaluation** (`lib/konsol/session/evaluator.rb`):
   - Captures stdout/stderr to StringIO
   - Wraps eval with Rails executor/reloader
   - Returns result with type, output, and exception info

### Key Directories

```
gem/
├── exe/konsol                    # CLI executable
├── lib/konsol/
│   ├── framing/                  # LSP-style Content-Length framing
│   ├── protocol/                 # JSON-RPC types (requests, responses, notifications)
│   ├── session/                  # Session management + code evaluation
│   ├── handlers/                 # Request handlers (lifecycle, konsol)
│   ├── util/                     # Case transforms (snake_case ↔ camelCase)
│   └── server.rb                 # Main server loop
├── spec/
│   ├── unit/                     # Unit tests
│   ├── integration/              # Full server flow tests
│   └── fixtures/test_app/        # Dummy Rails app for testing
└── sorbet/                       # Type definitions and RBI stubs

vscode-extension/
├── src/extension.ts              # Extension entry point
├── shared/                       # Shared types between extension and webview
│   ├── types.ts                  # Enums, interfaces
│   └── events.ts                 # Zod schemas for message validation
└── webview/                      # React 19 webview (planned)
```

### JSON-RPC Protocol

All messages use LSP-style framing. Key methods:
- `initialize` / `shutdown` / `exit` - Lifecycle
- `konsol/session.create` - Create a new session
- `konsol/eval` - Evaluate code in a session
- `konsol/interrupt` - Interrupt evaluation

Error codes: Standard JSON-RPC codes (-32700 to -32603) plus custom codes (-32001 to -32005) for session errors.

## Code Conventions

### Ruby (Gem)

- **Type System**: Sorbet strict mode. All new code must include `sig` blocks with type signatures.
- **Target Ruby**: 3.1+
- **Linting**: RuboCop with performance, rake, rspec, and sorbet plugins enabled
- **Case Conversion**: Ruby uses snake_case internally; JSON-RPC uses camelCase at the protocol boundary

### TypeScript (VSCode Extension)

- **State Management**: Zustand stores are encapsulated—only hooks and mutators are exported
- **Validation**: Zod schemas for runtime validation with `z.infer<>` for type inference
- **UI Components**: vscode-elements web components (not deprecated @vscode/webview-ui-toolkit)
- **React**: Version 19 with native web component support
- **Build**: esbuild via Bun for fast bundling
