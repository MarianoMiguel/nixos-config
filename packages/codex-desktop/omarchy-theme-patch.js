"use strict";

const RUNTIME_VERSION = "themeport-electron-css-v1";
const RUNTIME_GLOBAL = "codexLinuxThemeportCssRuntime";
const STYLESHEET_ENV = "CODEX_LINUX_OMARCHY_STYLESHEET";
const DEFAULT_STYLESHEET = "/home/mariano/.config/omarchy/current/theme/codex-desktop.css";
const STYLE_ELEMENT_ID = "codex-linux-themeport-style";

function omarchyThemeMainRuntimeSource() {
  return `
;(()=>{
const VERSION=${JSON.stringify(RUNTIME_VERSION)};
const GLOBAL_KEY=${JSON.stringify(RUNTIME_GLOBAL)};
const STYLESHEET_ENV=${JSON.stringify(STYLESHEET_ENV)};
const DEFAULT_STYLESHEET=${JSON.stringify(DEFAULT_STYLESHEET)};
const STYLE_ELEMENT_ID=${JSON.stringify(STYLE_ELEMENT_ID)};
if(globalThis[GLOBAL_KEY]?.version===VERSION)return;
try{globalThis[GLOBAL_KEY]?.cleanup?.()}catch{}
const electron=require("electron");
const fs=require("node:fs");
const stylesheet=process.env[STYLESHEET_ENV]||DEFAULT_STYLESHEET;
const listeners=new Map();
let css=null;
let interval=null;
function usable(contents){return contents!=null&&!contents.isDestroyed?.()&&typeof contents.executeJavaScript==="function"}
async function apply(contents){
  if(css==null||!usable(contents))return;
  try{
    const script="(()=>{let style=document.getElementById("+JSON.stringify(STYLE_ELEMENT_ID)+");if(!style){style=document.createElement('style');style.id="+JSON.stringify(STYLE_ELEMENT_ID)+";(document.head||document.documentElement).appendChild(style)}style.textContent="+JSON.stringify(css)+"})()";
    await contents.executeJavaScript(script,true);
    console.log("[themeport] applied desktop CSS webContentsId="+contents.id+" url="+(contents.getURL?.()??""));
  }catch(error){console.error("[themeport] could not apply desktop CSS webContentsId="+contents.id,error)}
}
function forget(contents){
  const handler=listeners.get(contents.id);
  if(handler!=null)contents.removeListener?.("did-finish-load",handler);
  listeners.delete(contents.id);
}
function watch(contents){
  if(!usable(contents)||listeners.has(contents.id))return;
  const reload=()=>{void apply(contents)};
  listeners.set(contents.id,reload);
  contents.on?.("did-finish-load",reload);
  reload();
}
function allContents(){try{return electron.webContents.getAllWebContents()}catch{return[]}}
async function refresh(){
  let next;
  try{next=await fs.promises.readFile(stylesheet,"utf8")}catch(error){
    console.error("[themeport] could not read desktop CSS path="+stylesheet,error);
    return;
  }
  if(next===css)return;
  css=next;
  const contents=allContents();
  for(const item of contents)watch(item);
  await Promise.all(contents.map(apply));
}
const onCreated=(_event,contents)=>watch(contents);
electron.app.on("web-contents-created",onCreated);
for(const contents of allContents())watch(contents);
void refresh();
interval=setInterval(()=>{void refresh()},2000);
interval.unref?.();
function cleanup(){
  electron.app.removeListener?.("web-contents-created",onCreated);
  if(interval!=null)clearInterval(interval);
  interval=null;
  for(const contents of allContents())forget(contents);
}
globalThis[GLOBAL_KEY]={version:VERSION,cleanup,refresh};
})();
`;
}

function applyOmarchyThemeMainRuntime(source) {
  if (typeof source !== "string" || source.includes(RUNTIME_VERSION)) {
    return source;
  }
  return `${source}\n${omarchyThemeMainRuntimeSource()}`;
}

module.exports = {
  RUNTIME_VERSION,
  RUNTIME_GLOBAL,
  STYLESHEET_ENV,
  DEFAULT_STYLESHEET,
  STYLE_ELEMENT_ID,
  descriptors: [
    {
      id: "omarchy-theme-electron-css",
      phase: "main-bundle",
      order: 20_780,
      ciPolicy: "optional",
      apply: applyOmarchyThemeMainRuntime,
    },
  ],
  applyOmarchyThemeMainRuntime,
  omarchyThemeMainRuntimeSource,
};
