const esbuild = require("esbuild");
const path = require("path");

const production = process.argv.includes("--production");
const watch = process.argv.includes("--watch");

/**
 * @type {import('esbuild').Plugin}
 */
const esbuildProblemMatcherPlugin = {
	name: "esbuild-problem-matcher",

	setup(build) {
		build.onStart(() => {
			console.log("[watch] build started");
		});
		build.onEnd((result) => {
			result.errors.forEach(({ text, location }) => {
				console.error(`✘ [ERROR] ${text}`);
				if (location) {
					console.error(`    ${location.file}:${location.line}:${location.column}:`);
				}
			});
			console.log("[watch] build finished");
		});
	},
};

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
};

/**
 * Webview build configuration (Browser) - Phase 2+
 * Uncomment when implementing React webview
 * @type {import('esbuild').BuildOptions}
 */
// const webviewConfig = {
// 	entryPoints: ["webview/main.tsx"],
// 	bundle: true,
// 	format: "esm",
// 	minify: production,
// 	sourcemap: !production,
// 	sourcesContent: false,
// 	platform: "browser",
// 	outfile: "dist/webview/main.js",
// 	external: [],
// 	logLevel: "silent",
// 	plugins: [esbuildProblemMatcherPlugin],
// 	loader: {
// 		".ttf": "file", // For Monaco editor fonts
// 		".css": "css",
// 	},
// 	define: {
// 		"process.env.NODE_ENV": production ? '"production"' : '"development"',
// 	},
// };

async function main() {
	// Build extension host
	const extensionCtx = await esbuild.context(extensionConfig);

	// Phase 2+: Uncomment to build webview
	// const webviewCtx = await esbuild.context(webviewConfig);

	if (watch) {
		await extensionCtx.watch();
		// await webviewCtx.watch();
	} else {
		await extensionCtx.rebuild();
		await extensionCtx.dispose();
		// await webviewCtx.rebuild();
		// await webviewCtx.dispose();
	}
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
