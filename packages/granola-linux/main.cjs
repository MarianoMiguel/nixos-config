const path = require("node:path");
const { app } = require("electron");

const appDir = path.join(__dirname, "app");
const resourcesDir = path.join(__dirname, "resources");

if (process.platform === "linux") {
  app.commandLine.appendSwitch(
    "enable-features",
    "WaylandWindowDecorations,WebRTCPipeWireCapturer",
  );
}

try {
  Object.defineProperty(process, "resourcesPath", {
    configurable: true,
    value: resourcesDir,
  });
} catch {
  process.resourcesPath = resourcesDir;
}

try {
  Object.defineProperty(app, "isPackaged", {
    configurable: true,
    get: () => true,
  });
} catch {
  // Fall back to Electron's default if the property is not configurable.
}

app.getAppPath = () => appDir;

require(path.join(appDir, "dist-electron", "main", "index.js"));
