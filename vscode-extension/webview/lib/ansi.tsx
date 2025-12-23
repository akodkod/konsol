import Anser from "anser"

export function parseAnsi(text: string): JSX.Element {
  const parsed = Anser.ansiToJson(text, { use_classes: true })

  return (
    <>
      {parsed.map((part, i) => {
        const classes = [
          part.fg ? part.fg : "",
          part.bg ? `ansi-bg-${part.bg.replace(/^ansi-/, "")}` : "",
          part.decoration ? `ansi-${part.decoration}` : "",
        ]
          .filter(Boolean)
          .join(" ")

        return classes ? (
          <span key={i} className={classes}>
            {part.content}
          </span>
        ) : (
          <span key={i}>{part.content}</span>
        )
      })}
    </>
  )
}
