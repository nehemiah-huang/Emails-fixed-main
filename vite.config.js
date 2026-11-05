
import { defineConfig } from "vite";
import { resolve } from "node:path";
import { readdirSync, existsSync, cpSync } from "node:fs";

const root = process.cwd();

const input = {
  main: resolve(root, "index.html"),
};

// Automatically discover all pages containing index.html
for (const folder of readdirSync(root, { withFileTypes: true })) {
  if (
    !folder.isDirectory() ||
    ["dist", "node_modules"].includes(folder.name) ||
    folder.name.startsWith(".")
  ) {
    continue;
  }

  const page = resolve(root, folder.name, "index.html");

  if (existsSync(page)) {
    input[folder.name] = page;
  }
}

// Include the Stay confirmation page if it exists
const stayConfirmation = resolve(root, "stay/confirmation.html");

if (existsSync(stayConfirmation)) {
  input.stayConfirmation = stayConfirmation;
}

export default defineConfig({
  plugins: [
    {
      name: "copy-static-files",

      closeBundle() {
        // Copy JavaScript files
        if (existsSync(resolve(root, "js"))) {
          cpSync(
            resolve(root, "js"),
            resolve(root, "dist/js"),
            { recursive: true }
          );
        }

        // Copy CSS files
        if (existsSync(resolve(root, "css"))) {
          cpSync(
            resolve(root, "css"),
            resolve(root, "dist/css"),
            { recursive: true }
          );
        }

        // Copy shared HTML partials
        if (existsSync(resolve(root, "partials"))) {
          cpSync(
            resolve(root, "partials"),
            resolve(root, "dist/partials"),
            { recursive: true }
          );
        }

        // Copy images
        if (existsSync(resolve(root, "images"))) {
          cpSync(
            resolve(root, "images"),
            resolve(root, "dist/images"),
            { recursive: true }
          );
        }
      },
    },
  ],

  build: {
    rollupOptions: {
      input,
    },
  },
});
