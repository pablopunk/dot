import { readFileSync, writeFileSync } from "node:fs";

const p = import.meta.resolve("prompts/lib/util/figures");
if (!p) process.exit(0);

const path = p.startsWith("file://") ? p.slice(7) : p;
let content = readFileSync(path, "utf8");
content = content.replace(/tick: '✔'/g, "tick: '✓'");
content = content.replace(/cross: '✖'/g, "cross: '×'");
content = content.replace(/pointer: '❯'/g, "pointer: '›'");
content = content.replace(/radioOn: '◉',\n  radioOff: '◯'/g, "radioOn: '',\n  radioOff: ''");
writeFileSync(path, content);
