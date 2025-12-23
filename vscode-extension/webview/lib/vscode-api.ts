type VSCodeAPI = {
  postMessage: (message: unknown) => void
  getState: () => unknown
  setState: (state: unknown) => void
}

function getVSCodeAPI(): VSCodeAPI {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const api = (window as any).acquireVsCodeApi
  if (typeof api !== "function") {
    console.error("acquireVsCodeApi not available - not running in VSCode webview")
    // Return a mock for debugging outside VSCode
    return {
      postMessage: (msg) => console.log("postMessage:", msg),
      getState: () => undefined,
      setState: () => {},
    }
  }
  return api()
}

// Acquire once, reuse everywhere
export const vscode: VSCodeAPI = getVSCodeAPI()
