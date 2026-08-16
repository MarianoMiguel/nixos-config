#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const appDir = path.resolve(process.argv[2] ?? "app");
const packageJsonPath = path.join(appDir, "package.json");

if (!fs.existsSync(packageJsonPath)) {
  throw new Error(`Granola package.json not found at ${packageJsonPath}`);
}

const appPackage = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
const mainPath = path.join(appDir, appPackage.main);
let mainSource = fs.readFileSync(mainPath, "utf8");

const microphonePermissionPattern =
  /await ([A-Za-z_$][\w$]*)\.systemPreferences\.askForMediaAccess\((["'`])microphone\2\)/;

const microphonePermissionAlreadyPatched =
  /typeof [A-Za-z_$][\w$]*\.systemPreferences\.askForMediaAccess===(["'`])function\1/.test(
    mainSource,
  );

if (!microphonePermissionAlreadyPatched && microphonePermissionPattern.test(mainSource)) {
  mainSource = mainSource.replace(
    microphonePermissionPattern,
    (_match, electron, quote) =>
      `typeof ${electron}.systemPreferences.askForMediaAccess===${quote}function${quote}?await ${electron}.systemPreferences.askForMediaAccess(${quote}microphone${quote}):!0`,
  );
} else if (
  !microphonePermissionAlreadyPatched &&
  !mainSource.includes("systemPreferences.askForMediaAccess")
) {
  throw new Error("Could not find Granola's microphone permission probe");
}

const updateListenerPattern = /\.autoUpdater\.on\((["'`])checking-for-update\1/;
const updateListener = updateListenerPattern.exec(mainSource);

if (!updateListener) {
  throw new Error("Could not find Granola's auto-updater initialization");
}

const updatePrefixStart = Math.max(0, updateListener.index - 600);
const updatePrefix = mainSource.slice(updatePrefixStart, updateListener.index);
const functionMatches = [
  ...updatePrefix.matchAll(/function ([A-Za-z_$][\w$]*)\(\)\{/g),
];
const updateInitializer = functionMatches.at(-1);

if (!updateInitializer) {
  throw new Error("Could not locate the auto-updater initializer function");
}

const initializerOffset =
  updatePrefixStart + updateInitializer.index + updateInitializer[0].length;
const initializerBody = mainSource.slice(initializerOffset, updateListener.index);

if (!initializerBody.includes("setInterval")) {
  throw new Error("The candidate auto-updater initializer does not set an interval");
}

if (!initializerBody.includes("process.platform")) {
  mainSource =
    mainSource.slice(0, initializerOffset) +
    "if(process.platform===`linux`)return;" +
    mainSource.slice(initializerOffset);
}

const clickDragPattern =
  /let ([A-Za-z_$][\w$]*)=require\((["'`])electron-click-drag-plugin\2\);\1=([A-Za-z_$][\w$]*)\.a\(\1\);/;

const clickDragMatch = clickDragPattern.exec(mainSource);

if (clickDragMatch) {
  const [_match, plugin, quote, interop] = clickDragMatch;
  mainSource = mainSource.replace(
    clickDragPattern,
    `let ${plugin}=process.platform===${quote}linux${quote}?{startDrag:()=>{}}:require(${quote}electron-click-drag-plugin${quote});${plugin}=${interop}.a(${plugin});`,
  );
} else if (
  !mainSource.includes(
    "process.platform===`linux`?{startDrag:()=>{}}:require(`electron-click-drag-plugin`)",
  ) &&
  !mainSource.includes(
    'process.platform==="linux"?{startDrag:()=>{}}:require("electron-click-drag-plugin")',
  )
) {
  throw new Error("Could not find Granola's native click-drag integration");
}

fs.writeFileSync(mainPath, mainSource);

const rendererRoot = path.join(appDir, "dist-app");
const rendererFiles = [];

function collectJavaScriptFiles(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      collectJavaScriptFiles(entryPath);
    } else if (entry.name.endsWith(".js")) {
      rendererFiles.push(entryPath);
    }
  }
}

collectJavaScriptFiles(rendererRoot);

const authPlatformPatches = [
  {
    from: "window.electron.platform===`win32`?`Windows`:window.electron.platform",
    to: "(window.electron.platform===`win32`||window.electron.platform===`linux`)?`Windows`:window.electron.platform",
  },
  {
    from: 'window.electron.platform==="win32"?"Windows":window.electron.platform',
    to: '(window.electron.platform==="win32"||window.electron.platform==="linux")?"Windows":window.electron.platform',
  },
];

let authPatchCount = 0;

for (const file of rendererFiles) {
  let source = fs.readFileSync(file, "utf8");
  const original = source;

  for (const { from, to } of authPlatformPatches) {
    const matches = source.split(from).length - 1;
    if (matches > 0) {
      source = source.split(from).join(to);
      authPatchCount += matches;
    }
  }

  if (source !== original) {
    fs.writeFileSync(file, source);
  }
}

if (authPatchCount === 0) {
  const alreadyPatched = rendererFiles.some((file) =>
    fs.readFileSync(file, "utf8").includes(
      "window.electron.platform===`linux`)?`Windows`",
    ),
  );
  if (!alreadyPatched) {
    throw new Error("Could not find Granola's authentication platform mapping");
  }
}

console.log(
  `Patched Granola ${appPackage.version} for Linux (${authPatchCount} authentication mapping${authPatchCount === 1 ? "" : "s"})`,
);
