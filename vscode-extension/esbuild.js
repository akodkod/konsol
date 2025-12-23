const esbuild = require("esbuild")

const production = process.argv.includes("--production")
const watch = process.argv.includes("--watch")

/**
 * @type {import('esbuild').Plugin}
 */
const esbuildProblemMatcherPlugin = {
  name: "esbuild-problem-matcher",

  setup(build) {
    build.onStart(() => {
      console.log("[watch] build started")
    })
    build.onEnd((result) => {
      result.errors.forEach(({ text, location }) => {
        console.error(`✘ [ERROR] ${text}`)
        if (location) {
          console.error(`    ${location.file}:${location.line}:${location.column}:`)
        }
      })
      console.log("[watch] build finished")
    })
  },
}

/**
 * Extension host build configuration (Node.js)
 * @type {import('esbuild').BuildOptions}
 */
const extensionConfig = {
  entryPoints: ["src/extension.ts"],
  bundle: true,
  format: "cjs",
  minify: production,
  sourcemap: !production,
  sourcesContent: false,
  platform: "node",
  outfile: "dist/extension.js",
  external: ["vscode"],
  logLevel: "silent",
  plugins: [esbuildProblemMatcherPlugin],
}

/**
 * Webview build configuration (Browser)
 * @type {import('esbuild').BuildOptions}
 */
const webviewConfig = {
  entryPoints: ["webview/main.tsx"],
  bundle: true,
  format: "esm",
  minify: production,
  sourcemap: !production,
  sourcesContent: false,
  platform: "browser",
  outfile: "dist/webview/main.js",
  external: [],
  logLevel: "silent",
  plugins: [esbuildProblemMatcherPlugin],
  loader: {
    ".css": "css",
    ".ttf": "dataurl",
  },
  jsx: "automatic",
  jsxImportSource: "react",
  define: {
    "process.env.NODE_ENV": production ? "\"production\"" : "\"development\"",
  },
}

async function main() {
  // Build extension host
  const extensionCtx = await esbuild.context(extensionConfig)

  // Build webview
  const webviewCtx = await esbuild.context(webviewConfig)

  if (watch) {
    await Promise.all([extensionCtx.watch(), webviewCtx.watch()])
  } else {
    await Promise.all([extensionCtx.rebuild(), webviewCtx.rebuild()])
    await Promise.all([extensionCtx.dispose(), webviewCtx.dispose()])
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
