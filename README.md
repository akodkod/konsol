# Konsol

A JSON-RPC 2.0 server providing a GUI-friendly Rails console backend with LSP-style framing over STDIN/STDOUT.

## Features

- JSON-RPC 2.0 protocol over stdio
- LSP-style Content-Length framing
- Session-based REPL with state persistence
- stdout/stderr capture
- Exception handling with backtraces
- Rails executor/reloader integration

## Installation

Add to your Rails application's Gemfile:

```ruby
gem "konsol"
```

Then run:

```bash
bundle install
```

## Usage

### Starting the Server

From your Rails application directory:

```bash
cd /path/to/rails/app
bundle exec konsol --stdio
```

### CLI Options

```
Usage: konsol [options]

Options:
    --stdio          Use stdio for JSON-RPC transport (required)
    --version, -v    Print version and exit
    --help, -h       Print this help and exit

Environment:
    RAILS_ENV        Rails environment (default: development)
```

### Protocol

Konsol uses JSON-RPC 2.0 with LSP-style framing:

```
Content-Length: <byte-length>\r\n
\r\n
<JSON-payload>
```

### Example Session

#### Initialize

Request:
```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"my-client"}}}
```

Response:
```json
{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"konsol","version":"0.1.0"},"capabilities":{"supportsInterrupt":false}}}
```

#### Create Session

Request:
```json
{"jsonrpc":"2.0","id":2,"method":"konsol/session.create"}
```

Response:
```json
{"jsonrpc":"2.0","id":2,"result":{"sessionId":"550e8400-e29b-41d4-a716-446655440000"}}
```

#### Evaluate Code

Request:
```json
{"jsonrpc":"2.0","id":3,"method":"konsol/eval","params":{"sessionId":"550e8400-e29b-41d4-a716-446655440000","code":"User.count"}}
```

Response:
```json
{"jsonrpc":"2.0","id":3,"result":{"value":"42","valueType":"Integer","stdout":"","stderr":""}}
```

#### State Persistence

Request:
```json
{"jsonrpc":"2.0","id":4,"method":"konsol/eval","params":{"sessionId":"...","code":"x = 123"}}
```

```json
{"jsonrpc":"2.0","id":5,"method":"konsol/eval","params":{"sessionId":"...","code":"x + 1"}}
```

Response:
```json
{"jsonrpc":"2.0","id":5,"result":{"value":"124","valueType":"Integer","stdout":"","stderr":""}}
```

#### Shutdown

Request:
```json
{"jsonrpc":"2.0","id":6,"method":"shutdown"}
```

Response:
```json
{"jsonrpc":"2.0","id":6,"result":null}
```

Notification:
```json
{"jsonrpc":"2.0","method":"exit"}
```

### Manual Testing with printf

```bash
cd /path/to/rails/app

# Send initialize request
printf 'Content-Length: 79\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"test"}}}' | bundle exec konsol --stdio
```

### Error Codes

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
| -32004 | EvalTimeout        | Evaluation timed out              |
| -32005 | ServerShuttingDown | Server is shutting down           |

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

```bash
bundle install
bundle exec rake spec
bundle exec rubocop
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
