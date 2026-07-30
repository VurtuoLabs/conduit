const { defineConfig } = require("eslint/config");
const eslintJs = require("@eslint/js");
const jestPlugin = require("eslint-plugin-jest");
const salesforceLwcConfig = require("@salesforce/eslint-config-lwc/recommended");

module.exports = defineConfig([
  {
    files: ["**/lwc/**/*.js"],
    extends: [salesforceLwcConfig]
  },
  {
    files: ["**/lwc/**/__tests__/**/*.js"],
    languageOptions: {
      globals: { ...jestPlugin.environments.globals.globals }
    },
    plugins: { jest: jestPlugin },
    extends: [
      eslintJs.configs.recommended,
      jestPlugin.configs["flat/recommended"]
    ]
  }
]);
