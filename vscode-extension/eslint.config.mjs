import cspellRecommended from "@cspell/eslint-plugin/recommended"
import { defineConfig } from "eslint/config"
import js from "@eslint/js"
import stylistic from "@stylistic/eslint-plugin"
import betterTailwindcss from "eslint-plugin-better-tailwindcss"
// oxlint-disable-next-line import/no-namespace
import * as betterTailwindcssDefaults from "eslint-plugin-better-tailwindcss/api/defaults"
import importNewlines from "eslint-plugin-import-newlines"
import unusedImports from "eslint-plugin-unused-imports"
import globals from "globals"
import ts from "typescript-eslint"
import reactHooks from "eslint-plugin-react-hooks"

const eslintConfig = defineConfig(
  cspellRecommended,
  reactHooks.configs.flat.recommended,
  {
    files: ["**/*.{js,mjs,cjs,ts,jsx,tsx}"],
  },
  {
    languageOptions: {
      parser: ts.parser,
      sourceType: "module",
      globals: {
        ...globals.browser,
        ...globals.node,
      },
    },
  },
  {
    ignores: [
      ".next/",
      ".nitro/",
      ".output/",
      ".vercel/",
      ".trigger/",
      ".tanstack/",
      ".react-email/",
      "node_modules/",
      "ios/",
      "android/",
      "dist/",
      "routeTree.gen.ts",
      "prisma/generated/",
    ],
  },
  {
    settings: {
      "better-tailwindcss": {
        entryPoint: "app/global.css",
        attributes: [
          "class",
          "className",
          ".*className",
        ],
        variables: [
          "className",
          ".*ClassName",
        ],
        callees: [
          ...betterTailwindcssDefaults.getDefaultCallees(),
          [
            "twLintClassNameValues",
            [
              {
                match: "objectValues",
                pathPattern: "(class|[cC]lassName)$",
              },
            ],
          ],
          [
            "twLintValues",
            [
              {
                match: "objectValues",
              },
            ],
          ],
          [
            "createElement",
            [
              {
                match: "objectValues",
                pathPattern: "(class|[cC]lassName)$",
              },
            ],
          ],
        ],
      },
    },
    plugins: {
      "better-tailwindcss": betterTailwindcss,
    },
    rules: {
      "better-tailwindcss/no-deprecated-classes": "error",
      "better-tailwindcss/no-conflicting-classes": "error",
      "better-tailwindcss/enforce-shorthand-classes": "error",
      "better-tailwindcss/enforce-consistent-variable-syntax": "error",
      "better-tailwindcss/enforce-consistent-important-position": "error",
      "better-tailwindcss/enforce-consistent-line-wrapping": ["error", {
        printWidth: 120,
      }],
      "better-tailwindcss/no-unregistered-classes": ["error", {
        ignore: ["toaster", "full-size-children-center"],
      }],
    },
  },
  {
    plugins: {
      js,
      "@stylistic": stylistic,
      "import-newlines": importNewlines,
      "unused-imports": unusedImports,
    },
    rules: {
      "no-useless-return": "error",
      "no-trailing-spaces": "error",
      "no-useless-assignment": "error",
      "no-multiple-empty-lines": ["error", {
        max: 1,
        maxBOF: 0,
        maxEOF: 0,
      }],

      "complexity": ["error", 10],
      "object-shorthand": ["error", "always"],

      "@stylistic/indent": ["error", 2],
      "@stylistic/semi": ["error", "never"],
      "@stylistic/comma-dangle": ["error", "always-multiline"],
      "@stylistic/arrow-parens": ["error", "always"],
      "@stylistic/object-curly-spacing": ["error", "always"],
      "@stylistic/eol-last": ["error", "always"],
      "@stylistic/padded-blocks": ["error", "never"],
      "@stylistic/quotes": ["error", "double", {
        avoidEscape: true,
      }],
      "@stylistic/quote-props": ["error", "consistent-as-needed"],
      "@stylistic/template-tag-spacing": ["error", "never"],

      "@stylistic/object-property-newline": ["error", {
        allowAllPropertiesOnSameLine: true,
      }],

      "@stylistic/key-spacing": ["error", {
        beforeColon: false,
        afterColon: true,
      }],

      "@stylistic/jsx-quotes": ["error", "prefer-double"],
      "@stylistic/jsx-curly-brace-presence": ["error", "never"],
      "@stylistic/jsx-curly-spacing": ["error", {
        when: "never", children: true,
      }],
      "@stylistic/jsx-max-props-per-line": ["error", {
        maximum: 1,
      }],
      "@stylistic/jsx-first-prop-new-line": ["error", "multiline"],
      "@stylistic/jsx-closing-bracket-location": "error",
      "@stylistic/jsx-sort-props": [
        "error",
        {
          reservedFirst: ["key", "ref"],
          shorthandFirst: true,
          noSortAlphabetically: true,
          callbacksLast: true,
        },
      ],
      // TODO[2025-09-01]: Figure out on how to exclude Zod from this rule
      // "@stylistic/newline-per-chained-call": ["error", { ignoreChainWithDepth: 1 }],
      "@stylistic/space-before-function-paren": [
        "error",
        {
          asyncArrow: "always",
          anonymous: "never",
          named: "never",
        },
      ],
      "@stylistic/type-annotation-spacing": [
        "error",
        {
          before: false,
          after: true,
          overrides: {
            arrow: {
              before: true,
              after: true,
            },
          },
        },
      ],
      "@stylistic/member-delimiter-style": [
        "error",
        {
          multiline: {
            delimiter: "none",
          },
        },
      ],
      "@stylistic/padding-line-between-statements": [
        "error",
        {
          blankLine: "always", prev: "block-like", next: "*",
        },
        {
          blankLine: "always", prev: ["const", "let"], next: "block-like",
        },
      ],
      "@stylistic/lines-between-class-members": [
        "error",
        {
          enforce: [
            {
              blankLine: "always", prev: "method", next: "method",
            },
          ],
        },
      ],

      "import-newlines/enforce": [
        "error",
        128,
      ],

      "unused-imports/no-unused-imports": "error",

      "no-restricted-syntax": [
        "error",
        {
          message: "Please remove dev functions before committing",
          selector: "Identifier[name=/dev_.*/]",
        },
        {
          message: "Don't default import from zod. Use: import * as z from \"zod\"",
          selector: "ImportDeclaration[source.value='zod'] > ImportDefaultSpecifier",
        },
        {
          message: "Sleep function is only for development",
          selector: "Identifier[name=sleep]",
        },
      ],

      "no-restricted-exports": [
        "error",
        {
          restrictedNamedExports: ["default"],
        },
      ],
    },
  },
  {
    // Lift complexity for React components
    files: ["**/*.tsx"],
    rules: {
      complexity: ["error", 20],
    },
  },
  {
    files: [
      "lib/modules/**/*.{ts,tsx}",
      "features/**/*.module.ts",
    ],
    rules: {
      "react-hooks/rules-of-hooks": "off",
    },
  },
)

export default eslintConfig
