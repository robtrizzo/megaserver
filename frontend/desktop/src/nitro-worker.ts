// This script runs in a utilityProcess to start the Nitro server
// Environment variables are passed from the main process

const serverDir = process.env.NITRO_SERVER_DIR;

if (!serverDir) {
  console.error("NITRO_SERVER_DIR environment variable is not set");
  process.exit(1);
}

const entryPath = `file://${serverDir.replace(/\\/g, "/")}/index.mjs`;

import(entryPath).catch((err: unknown) => {
  console.error("Failed to start Nitro server:", err);
  process.exit(1);
});
