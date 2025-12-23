import * as vscode from "vscode"
import { KonsolViewProvider } from "./konsol-view-provider"

let provider: KonsolViewProvider | undefined

export function activate(context: vscode.ExtensionContext): void {
  const outputChannel = vscode.window.createOutputChannel("Konsol")
  outputChannel.appendLine("Konsol extension activated")

  provider = new KonsolViewProvider(context.extensionUri, outputChannel)

  // Register the webview view provider
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(
      KonsolViewProvider.viewType,
      provider,
      { webviewOptions: { retainContextWhenHidden: true } },
    ),
  )

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand("konsol.start", () => provider?.start()),
    vscode.commands.registerCommand("konsol.stop", () => provider?.stop()),
    vscode.commands.registerCommand("konsol.clear", () => provider?.clear()),
  )

  context.subscriptions.push(outputChannel)
}

export function deactivate(): void {
  provider?.stop()
}
