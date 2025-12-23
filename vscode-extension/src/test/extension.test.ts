import * as assert from "assert"
import * as vscode from "vscode"

suite("Extension Test Suite", () => {
  vscode.window.showInformationMessage("Start all tests.")

  test("Extension should be present", () => {
    const extension = vscode.extensions.getExtension("konsol.konsol")
    assert.ok(extension, "Extension should be registered")
  })

  test("Extension should activate", async () => {
    const extension = vscode.extensions.getExtension("konsol.konsol")
    if (extension) {
      await extension.activate()
      assert.strictEqual(extension.isActive, true)
    }
  })

  test("Commands should be registered", async () => {
    const commands = await vscode.commands.getCommands(true)
    assert.ok(commands.includes("konsol.start"), "konsol.start command should exist")
    assert.ok(commands.includes("konsol.stop"), "konsol.stop command should exist")
    assert.ok(commands.includes("konsol.clear"), "konsol.clear command should exist")
  })
})
