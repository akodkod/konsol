import * as vscode from "vscode"
import { KonsolClient } from "./konsol-client"

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

type WebviewMessage =
  | { type: "ready" }
  | { type: "eval", code: string }
  | { type: "interrupt" }
  | { type: "clear" }
  | { type: "connect" }

// ─────────────────────────────────────────────────────────────────────────────
// Utilities
// ─────────────────────────────────────────────────────────────────────────────

function getNonce(): string {
  let text = ""
  const possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  for (let i = 0; i < 32; i++) {
    text += possible.charAt(Math.floor(Math.random() * possible.length))
  }
  return text
}

// ─────────────────────────────────────────────────────────────────────────────
// KonsolViewProvider
// ─────────────────────────────────────────────────────────────────────────────

export class KonsolViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = "konsol.panel"

  private view?: vscode.WebviewView
  private client: KonsolClient
  private outputChannel: vscode.OutputChannel

  constructor(
    private readonly extensionUri: vscode.Uri,
    outputChannel: vscode.OutputChannel,
  ) {
    this.client = new KonsolClient()
    this.outputChannel = outputChannel
  }

  resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken,
  ): void {
    this.view = webviewView

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri],
    }

    webviewView.webview.html = this.getHtmlContent(webviewView.webview)

    // Handle messages from webview
    webviewView.webview.onDidReceiveMessage(async (message: WebviewMessage) => {
      switch (message.type) {
      case "ready":
        this.outputChannel.appendLine("Webview ready")
        break
      case "eval":
        await this.handleEval(message.code)
        break
      case "interrupt":
        await this.handleInterrupt()
        break
      case "clear":
        // Clear is handled in webview
        break
      case "connect":
        await this.start()
        break
      }
    })

    // Clean up on dispose
    webviewView.onDidDispose(() => {
      this.stop()
    })
  }

  async start(): Promise<void> {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0]
    if (!workspaceFolder) {
      vscode.window.showErrorMessage("No workspace folder open")
      return
    }

    const config = vscode.workspace.getConfiguration("konsol")
    const railsEnv = config.get<string>("railsEnv", "development")

    try {
      this.outputChannel.appendLine(`Starting Konsol in ${workspaceFolder.uri.fsPath} (${railsEnv})`)
      await this.client.start(workspaceFolder.uri.fsPath, railsEnv)
      const sessionId = await this.client.createSession()
      this.outputChannel.appendLine(`Session created: ${sessionId}`)

      // Set up notification handlers
      this.client.onNotification("konsol/stdout", (params) => {
        this.postMessage({ type: "notification", method: "konsol/stdout", params })
      })

      this.client.onNotification("konsol/stderr", (params) => {
        this.postMessage({ type: "notification", method: "konsol/stderr", params })
      })

      this.client.onNotification("konsol/status", (params) => {
        this.postMessage({ type: "notification", method: "konsol/status", params })
      })

      this.postMessage({ type: "connected", sessionId })
      vscode.window.showInformationMessage("Konsol session started")
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      vscode.window.showErrorMessage(`Failed to start Konsol: ${message}`)
      this.outputChannel.appendLine(`Error: ${message}`)
    }
  }

  async stop(): Promise<void> {
    try {
      await this.client.shutdown()
      this.postMessage({ type: "disconnected" })
      this.outputChannel.appendLine("Konsol session stopped")
    } catch (error) {
      // Ignore shutdown errors
      this.outputChannel.appendLine(`Shutdown error (ignored): ${error}`)
    }
  }

  clear(): void {
    this.postMessage({ type: "clear" })
  }

  private async handleEval(code: string): Promise<void> {
    try {
      this.outputChannel.appendLine(`Evaluating: ${code}`)
      const result = await this.client.evaluate(code)
      this.outputChannel.appendLine(`Result: ${JSON.stringify(result)}`)
      this.postMessage({ type: "result", data: result })
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      this.outputChannel.appendLine(`Eval error: ${message}`)
      this.postMessage({ type: "error", message })
    }
  }

  private async handleInterrupt(): Promise<void> {
    try {
      await this.client.interrupt()
      this.outputChannel.appendLine("Interrupted")
    } catch (error) {
      // Ignore interrupt errors
      this.outputChannel.appendLine(`Interrupt error (ignored): ${error}`)
    }
  }

  private postMessage(message: unknown): void {
    this.view?.webview.postMessage(message)
  }

  private getHtmlContent(webview: vscode.Webview): string {
    const nonce = getNonce()

    // Get URIs for bundled React app
    const scriptUri = webview.asWebviewUri(
      vscode.Uri.joinPath(this.extensionUri, "dist", "webview", "main.js"),
    )

    const styleUri = webview.asWebviewUri(
      vscode.Uri.joinPath(this.extensionUri, "dist", "webview", "main.css"),
    )

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="
    default-src 'none';
    style-src ${webview.cspSource} 'unsafe-inline';
    script-src 'nonce-${nonce}';
    font-src ${webview.cspSource} data:;
  ">
  <link id="vscode-codicon-stylesheet" rel="stylesheet" href="${styleUri}">
  <title>Konsol</title>
</head>
<body>
  <div id="root"></div>
  <script nonce="${nonce}" type="module" src="${scriptUri}"></script>
</body>
</html>`
  }
}
