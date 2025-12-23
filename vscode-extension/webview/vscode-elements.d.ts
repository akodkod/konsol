import type { VscodeButton } from "@vscode-elements/elements"

type WebComponentProps<T> = Partial<T> & {
  class?: string
  children?: React.ReactNode
}

declare global {
  namespace JSX {
    interface IntrinsicElements {
      "vscode-button": WebComponentProps<VscodeButton> & {
        appearance?: "primary" | "secondary" | "icon"
        disabled?: boolean | undefined
        onClick?: (event: Event) => void
      }
    }
  }
}

export {}
