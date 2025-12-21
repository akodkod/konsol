# Konsol Implementation Plan

You are Claude Code. Enter PLANNING MODE and produce an implementation plan first (no coding yet). The goal is to build ONLY the Ruby gem "server part" for a GUI Rails console backend. Client-agnostic: for testing we will send direct JSON-RPC requests over stdio.

---

## Project Name

- Gem name: `konsol`
- Executable: `konsol`

---

## Version Requirements

- Ruby: `>= 3.1.0`
- Rails: 7.0+ (tested)

---

## Key Goals (gem-only, for now)

- Provide a JSON-RPC 2.0 server over STDIN/STDOUT using LSP-style framing (Content-Length headers).
- Provide a minimal console runtime API to:
  - create a session
  - eval code in that session
  - preserve session state across multiple eval calls
- Provide integration tests using a tiny real Rails app fixture and direct JSON-RPC messages.

---

## Gem Structure

```
konsol/
├── lib/
│   ├── konsol.rb                    # Main entry, version, autoloads
│   └── konsol/
│       ├── version.rb
│       ├── server.rb                # Main server loop
│       ├── framing/
│       │   ├── reader.rb            # Content-Length parser
│       │   └── writer.rb            # Content-Length encoder
│       ├── protocol/
│       │   ├── message.rb           # Base T::Struct for JSON-RPC
│       │   ├── methods.rb           # T::Enum of method names
│       │   ├── error_codes.rb       # T::Enum of error codes
│       │   ├── requests/            # T::Struct per request type
│       │   ├── responses/           # T::Struct per response type
│       │   └── notifications/       # T::Struct per notification type
│       ├── handlers/
│       │   ├── lifecycle.rb         # initialize, shutdown, exit
│       │   └── konsol.rb            # session.create, eval, interrupt
│       ├── session/
│       │   ├── manager.rb           # Session registry
│       │   ├── session.rb           # Single session (binding, state)
│       │   └── evaluator.rb         # Eval logic with capture
│       └── util/
│           └── case_transform.rb    # camelCase <-> snake_case
├── exe/
│   └── konsol                       # Executable entry point
├── spec/
│   ├── spec_helper.rb
│   ├── unit/                        # Unit tests
│   ├── integration/                 # JSON-RPC integration tests
│   └── fixtures/
│       └── test_app/                # Minimal Rails app
├── sorbet/
│   └── config
├── konsol.gemspec
├── Gemfile
└── README.md
```

---

## Dependencies

**Runtime:**
```ruby
spec.add_runtime_dependency "sorbet-runtime", "~> 0.6"
```

**Development:**
```ruby
spec.add_development_dependency "sorbet", "~> 0.6"
spec.add_development_dependency "tapioca", "~> 0.17.10"
spec.add_development_dependency "rspec", "~> 3.13"
```

---

## Typing Requirements (Sorbet)

- Use Sorbet for typing across the gem codebase.
- Use `T::Struct` for all protocol message shapes (requests, responses, notifications, params/results, errors).
- Use `T::Enum` for:
  - method names (RPC methods / event names)
  - error codes/categories
- Sorbet typing applies to:
  - the framing reader/writer
  - message parsing/serialization
  - the session manager and evaluator
  - the notification/event payloads

---

## Casing Requirements

- JSON-RPC payloads MUST use camelCase for keys.
- Internally in Ruby, use snake_case.
- Implement automatic conversion between camelCase <-> snake_case for:
  - incoming params (decode)
  - outgoing results/errors/notifications (encode)
- The conversion should be consistent, tested, and applied at the protocol boundary (single place in `util/case_transform.rb`).

---

## Framing Format (LSP-style)

```
Content-Length: <byte-length>\r\n
\r\n
<JSON-UTF8-payload>
```

**Specifics:**
- Encoding: UTF-8 (no BOM)
- `Content-Length` is byte count, not character count
- Only `Content-Length` header required; other headers ignored if present
- No trailing `\r\n` after payload

**Reader logic:**
```ruby
# Read headers until empty line
loop do
  line = io.gets("\r\n")
  break if line == "\r\n"
  if line =~ /^Content-Length:\s*(\d+)/i
    length = $1.to_i
  end
end
# Read exactly `length` bytes
payload = io.read(length)
```

---

## Protocol

### JSON-RPC Error Codes

| Code   | Constant           | Description                       |
|--------|--------------------|-----------------------------------|
| -32700 | ParseError         | Invalid JSON                      |
| -32600 | InvalidRequest     | Not a valid request object        |
| -32601 | MethodNotFound     | Method does not exist             |
| -32602 | InvalidParams      | Invalid method parameters         |
| -32603 | InternalError      | Internal server error             |
| -32001 | SessionNotFound    | Session ID does not exist         |
| -32002 | SessionBusy        | Session is currently evaluating   |
| -32003 | RailsBootFailed    | Failed to boot Rails environment  |
| -32004 | EvalTimeout        | Evaluation timed out (future use) |
| -32005 | ServerShuttingDown | Server is shutting down           |

**Error response structure:**
```ruby
class Konsol::Protocol::ErrorData < T::Struct
  const :code, Integer
  const :message, String
  const :data, T.nilable(T::Hash[String, T.untyped])  # Optional details
end
```

### Request ID Handling

- Accept string, integer, or null
- Echo back exactly as received (preserve type)

```ruby
const :id, T.any(String, Integer, NilClass)
```

### Empty Params

The `params` key is optional for methods with no parameters. Both are valid:
```json
{"jsonrpc":"2.0","id":1,"method":"shutdown"}
{"jsonrpc":"2.0","id":1,"method":"shutdown","params":{}}
```

---

### 1. LSP-like Lifecycle

#### `initialize`

**Request params:**
```ruby
class InitializeParams < T::Struct
  const :process_id, T.nilable(Integer), default: nil  # Client PID (optional)
  const :client_info, T.nilable(ClientInfo), default: nil

  class ClientInfo < T::Struct
    const :name, String
    const :version, T.nilable(String), default: nil
  end
end
```

**Response result:**
```ruby
class InitializeResult < T::Struct
  const :server_info, ServerInfo
  const :capabilities, Capabilities

  class ServerInfo < T::Struct
    const :name, String              # "konsol"
    const :version, String           # Konsol::VERSION
  end

  class Capabilities < T::Struct
    const :supports_interrupt, T::Boolean, default: false  # v1: false
  end
end
```

**Example exchange:**
```json
// Request
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"test-client"}}}

// Response
{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"konsol","version":"0.1.0"},"capabilities":{"supportsInterrupt":false}}}
```

#### `shutdown`

- params: none
- result: `null`
- Invalidates all sessions, server prepares to exit

#### `exit`

- Notification (no id, no response)
- Server exits with code 0 if shutdown was called, 1 otherwise

#### `$/cancelRequest`

- params: `{ id: string | number }` (ID of request to cancel)
- v1: Always returns success, does nothing internally
- Future: Set interrupt flag on session, check in eval loop

---

### 2. Konsol Console API

#### `konsol/session.create`

- params: `{}`
- result: `{ sessionId: string }`

**Notes:**
- Session ID format: UUID v4 string (e.g., `"550e8400-e29b-41d4-a716-446655440000"`)
- Do NOT include appPath in params
- Assume the server process is launched from within the target Rails app context:
  - current working directory is the Rails root
  - Bundler/Gemfile is the Rails app's
  - `RAILS_ENV` may already be set

#### `konsol/eval`

- params: `{ sessionId: string, code: string }`
- result:
```json
{
  "value": "string",
  "valueType": "string?",
  "stdout": "string",
  "stderr": "string",
  "exception": {
    "class": "string",
    "message": "string",
    "backtrace": ["string"]
  }
}
```

#### `konsol/interrupt`

- params: `{ sessionId: string }`
- result: `{ success: boolean }`
- v1: Stub that returns `{ success: true }` but does not actually interrupt

---

### 3. Notifications (server -> client)

Defined for future use. **Not sent in v1** (output is buffered and returned in eval result).

- `konsol/stdout` - `{ sessionId: string, chunk: string }`
- `konsol/stderr` - `{ sessionId: string, chunk: string }`
- `konsol/status` - `{ sessionId: string, busy: boolean }`

Use `T::Enum` for notification names and `T::Struct` for payloads.

---

## Output Capture Strategy

### v1: Buffered Only

- During eval, `$stdout` and `$stderr` are captured to StringIO
- After eval completes, full content returned in result fields
- `konsol/stdout` and `konsol/stderr` notifications are NOT sent in v1
- Notifications defined in protocol for future streaming support

---

## Rails Boot / Session Strategy

### Boot Process

On `konsol/session.create`, boot Rails (once per process):
1. `require "config/environment"`
2. Call `Rails.application.load_console` if available

### Session Binding

```ruby
def create_session_binding
  context = Object.new

  # Add Rails console helpers if available
  if defined?(Rails::ConsoleMethods)
    context.extend(Rails::ConsoleMethods)
  end

  context.instance_eval { binding }
end
```

**Available in binding (v1):**
- All Rails constants (after boot)
- `app` (Rails.application)
- `helper` (ActionController helpers, if Rails::ConsoleMethods loaded)
- `reload!` (via Rails::ConsoleMethods)

**Not included (v1):**
- IRB/Pry-specific methods
- Custom Konsol helpers (future)

### State Persistence

- Each session holds a persistent `Binding` used across eval calls
- Eval uses `Kernel.eval(code, binding, "(konsol)", 1)`

### Executor/Reloader Wrapping

Wrap eval with Rails executor/reloader if available:
```ruby
Rails.application.executor.wrap do
  Rails.application.reloader.wrap do
    # eval here
  end
end
```
Handle method availability gracefully.

### Output Capture

- Capture `$stdout`/`$stderr` during eval using StringIO
- Restore original streams after eval
- v1: Single-threaded, no cross-session interference concern
- Future: Thread-local capture for concurrent evals

---

## Session Lifecycle

### Session States

```ruby
class SessionState < T::Enum
  enums do
    Idle = new
    Busy = new        # Eval in progress
    Interrupted = new # Future use
  end
end
```

### Lifecycle Rules

- Sessions persist until `shutdown` or process exit
- On `shutdown`: all sessions invalidated, pending evals return ServerShuttingDown error
- No timeout in v1 (process assumed short-lived)
- No max sessions limit in v1 (single-client assumption)

---

## CLI Interface

```
Usage: konsol [options]

Options:
    --stdio          Use stdio for JSON-RPC transport (required for v1)
    --version, -v    Print version and exit
    --help, -h       Print this help and exit

Environment:
    RAILS_ENV        Rails environment (default: development)
    KONSOL_LOG       Log file path (default: none, silent)

Examples:
    cd /path/to/rails/app && bundle exec konsol --stdio
```

### Exit Codes

- `0` - Clean shutdown via `exit` notification after `shutdown`
- `1` - Error (boot failure, invalid args, exit without shutdown)
- `130` - SIGINT

---

## Signal Handling

```ruby
Signal.trap("INT") do
  @shutdown_requested = true
end

Signal.trap("TERM") do
  @shutdown_requested = true
end
```

**Behavior:**
- SIGINT/SIGTERM: Set flag, finish current message, then clean shutdown
- No `exit` notification sent by server (client should handle disconnect)
- Main loop checks `@shutdown_requested` between messages

---

## Repository Contents

### 1. Konsol Gem

- stdio JSON-RPC server implementation with LSP framing
- Sorbet config and typed code
- README with:
  - how to run `konsol` from a Rails app root
  - how to send manual framed JSON-RPC requests (example using printf)
  - example requests/responses for initialize, session.create, eval

### 2. Tiny Rails Fixture App + Integration Tests

Create a minimal Rails app committed into the repo:
- Location: `spec/fixtures/test_app`
- sqlite, minimal config
- Include Konsol gem via Gemfile `path:` reference

**Integration tests (RSpec):**
- Spawn `bundle exec konsol --stdio` from within the fixture app directory
- Send framed JSON-RPC requests
- Parse framed responses

**Required test coverage:**
- `initialize` works and returns capabilities
- `shutdown` + `exit` lifecycle
- `konsol/session.create` works and returns sessionId
- `konsol/eval` can reference Rails constants and environment
- State persists: `x = 123` then `x + 1` returns `124`
- stdout capture: `puts "hi"` returns stdout `"hi\n"`
- stderr capture: `$stderr.puts "err"` returns stderr `"err\n"`
- Exception capture: `raise "boom"` returns exception struct
- Error handling: invalid session ID returns SessionNotFound error
- Error handling: malformed JSON returns ParseError

---

## Important Constraints / Non-Goals for v1

- No UI client, no VSCode extension yet
- No Pry integration
- No `konsol/session.reset` (not planned for v1)
- No full LSP features; only LSP framing + lifecycle for easier VSCode integration later
- No streaming output (notifications defined but not sent)
- No actual interrupt support (stub only)
- Multi-client daemon over sockets: optional to mention as future evolution, do not implement

---

## Future Considerations (out of scope for v1)

- Streaming output via notifications
- Real interrupt support with Thread#raise or similar
- Multiple concurrent sessions with thread-local capture
- Socket transport for multi-client daemon mode
- Session timeout/cleanup
- Custom Konsol helpers in binding
- Pry integration
