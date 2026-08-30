#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const vm = require("node:vm");

const {
  DEFAULT_STYLESHEET,
  RUNTIME_VERSION,
  STYLE_ELEMENT_ID,
  applyOmarchyThemeMainRuntime,
  omarchyThemeMainRuntimeSource,
} = require("./omarchy-theme-patch.js");

test("main bundle patch is idempotent", () => {
  const source = "console.log('codex');";
  const patched = applyOmarchyThemeMainRuntime(source);
  assert.notEqual(patched, source);
  assert.equal(applyOmarchyThemeMainRuntime(patched), patched);
  assert.match(patched, new RegExp(RUNTIME_VERSION));
  assert.match(patched, /executeJavaScript/);
  assert.match(patched, new RegExp(DEFAULT_STYLESHEET.replaceAll("/", "\\/")));
});

test("runtime injects and refreshes CSS through Electron", async () => {
  let fileContents = ":root { --themeport-test: first; }";
  const executed = [];
  const contentListeners = new Map();
  const appListeners = new Map();
  let intervalCallback;

  const contents = {
    id: 7,
    isDestroyed: () => false,
    executeJavaScript: async (script, userGesture) => executed.push([script, userGesture]),
    on: (event, handler) => contentListeners.set(event, handler),
    once: (event, handler) => contentListeners.set(event, handler),
    removeListener: (event, handler) => {
      if (contentListeners.get(event) === handler) contentListeners.delete(event);
    },
  };
  const sandbox = {
    process: { env: {} },
    require(id) {
      if (id === "electron") {
        return {
          app: {
            on: (event, handler) => appListeners.set(event, handler),
            removeListener: (event, handler) => {
              if (appListeners.get(event) === handler) appListeners.delete(event);
            },
          },
          webContents: { getAllWebContents: () => [contents] },
        };
      }
      if (id === "node:fs") {
        return { promises: { readFile: async (path) => {
          assert.equal(path, DEFAULT_STYLESHEET);
          return fileContents;
        } } };
      }
      throw new Error(`unexpected require: ${id}`);
    },
    setInterval(callback) {
      intervalCallback = callback;
      return { unref() {} };
    },
    clearInterval() {},
  };

  vm.createContext(sandbox);
  vm.runInContext(omarchyThemeMainRuntimeSource(), sandbox);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(executed.length, 1);
  assert.match(executed[0][0], new RegExp(STYLE_ELEMENT_ID));
  assert.match(executed[0][0], /themeport-test: first/);
  assert.equal(executed[0][1], true);
  assert.equal(appListeners.has("web-contents-created"), true);
  assert.equal(contentListeners.has("did-finish-load"), true);

  fileContents = ":root { --themeport-test: second; }";
  intervalCallback();
  await new Promise((resolve) => setImmediate(resolve));
  assert.match(executed.at(-1)[0], /themeport-test: second/);
  assert.equal(executed.at(-1)[1], true);
});
