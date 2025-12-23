import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "./App"
import "./styles/konsol.css"
import "@vscode/codicons/dist/codicon.css"

// Import vscode-elements (React 19 native web component support)
import "@vscode-elements/elements/dist/vscode-button"

const root = document.getElementById("root")
if (root) {
  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>
  )
}
