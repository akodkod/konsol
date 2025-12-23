import * as childProcess from "child_process"
import * as rpc from "vscode-jsonrpc/node"

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

type InitializeResult = {
  serverInfo: { name: string, version: string }
  capabilities: { supportsInterrupt: boolean }
}

type SessionCreateResult = {
  sessionId: string
}

type EvalResult = {
  value: string
  valueType?: string
  stdout: string
  stderr: string
  exception?: {
    class: string
    message: string
    backtrace: string[]
  }
}

type InterruptResult = {
  success: boolean
}

type NotificationHandler = (params: unknown) => void

// ─────────────────────────────────────────────────────────────────────────────
// KonsolClient
// ─────────────────────────────────────────────────────────────────────────────

export class KonsolClient {
  private process: childProcess.ChildProcess | null = null
  private connection: rpc.MessageConnection | null = null
  private sessionId: string | null = null
  private initialized = false
  private notificationHandlers: Map<string, NotificationHandler> = new Map()

  async start(workspaceRoot: string, railsEnv: string): Promise<void> {
    // Spawn konsol process
    this.process = childProcess.spawn("bundle", ["exec", "konsol", "--stdio"], {
      cwd: workspaceRoot,
      env: { ...process.env, RAILS_ENV: railsEnv },
      shell: true,
    })

    // Handle process errors
    this.process.on("error", (error) => {
      console.error("Konsol process error:", error)
      this.cleanup()
    })

    this.process.on("exit", (code, signal) => {
      console.log(`Konsol process exited with code ${code}, signal ${signal}`)
      this.cleanup()
    })

    // Capture stderr for debugging
    this.process.stderr?.on("data", (data: Buffer) => {
      console.error("Konsol stderr:", data.toString())
    })

    // Create JSON-RPC connection with LSP-style framing
    this.connection = rpc.createMessageConnection(
      new rpc.StreamMessageReader(this.process.stdout!),
      new rpc.StreamMessageWriter(this.process.stdin!),
    )

    // Set up notification handlers
    this.connection.onNotification((method: string, params: unknown) => {
      const handler = this.notificationHandlers.get(method)
      if (handler) {
        handler(params)
      }
    })

    this.connection.listen()

    // Initialize handshake
    const initResult = await this.connection.sendRequest<InitializeResult>("initialize", {
      processId: process.pid,
      clientInfo: { name: "vscode-konsol", version: "0.1.0" },
    })

    this.initialized = true
    console.log(`Connected to ${initResult.serverInfo.name} v${initResult.serverInfo.version}`)
  }

  async createSession(): Promise<string> {
    if (!this.connection || !this.initialized) {
      throw new Error("Client not initialized")
    }

    const result = await this.connection.sendRequest<SessionCreateResult>("konsol/session.create", {})
    this.sessionId = result.sessionId
    return this.sessionId
  }

  async evaluate(code: string): Promise<EvalResult> {
    if (!this.connection || !this.sessionId) {
      throw new Error("No active session")
    }

    return this.connection.sendRequest<EvalResult>("konsol/eval", {
      sessionId: this.sessionId,
      code,
    })
  }

  async interrupt(): Promise<InterruptResult> {
    if (!this.connection || !this.sessionId) {
      throw new Error("No active session")
    }

    return this.connection.sendRequest<InterruptResult>("konsol/interrupt", {
      sessionId: this.sessionId,
    })
  }

  onNotification(method: string, handler: NotificationHandler): void {
    this.notificationHandlers.set(method, handler)
  }

  async shutdown(): Promise<void> {
    if (this.connection && this.initialized) {
      try {
        await this.connection.sendRequest("shutdown")
        this.connection.sendNotification("exit")
      } catch (error) {
        // Ignore errors during shutdown
        console.log("Shutdown error (ignored):", error)
      }
    }
    this.cleanup()
  }

  private cleanup(): void {
    this.connection?.dispose()
    this.process?.kill()
    this.connection = null
    this.process = null
    this.sessionId = null
    this.initialized = false
    this.notificationHandlers.clear()
  }

  get isConnected(): boolean {
    return this.initialized && this.connection !== null
  }

  get currentSessionId(): string | null {
    return this.sessionId
  }
}
