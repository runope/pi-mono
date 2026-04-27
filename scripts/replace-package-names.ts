#!/usr/bin/env bun
/**
 * 安全替换包名的脚本
 * 保持 UTF-8 编码，避免破坏文件
 */

import { readFileSync, writeFileSync, readdirSync, statSync } from "fs";
import { join, extname } from "path";

const REPLACEMENTS: Record<string, string> = {
  "@runope/pi-ai": "@runope/pi-ai",
  "@runope/pi-tui": "@runope/pi-tui",
  "@runope/pi-agent-core": "@runope/pi-agent-core",
  "@runope/pi-coding-agent": "@runope/pi-coding-agent",
  "@runope/pi-mom": "@runope/pi-mom",
  "@runope/pi-pods": "@runope/pi-pods",
  "@runope/pi-web-ui": "@runope/pi-web-ui",
  "@runope/pi-agent": "@runope/pi-agent",
};

const VALID_EXTENSIONS = [".ts", ".tsx", ".js", ".jsx", ".json"];
const IGNORE_DIRS = ["node_modules", ".git", "dist", ".bun"];

function walkDir(dir: string, files: string[] = []): string[] {
  const entries = readdirSync(dir);
  for (const entry of entries) {
    const fullPath = join(dir, entry);
    const stat = statSync(fullPath);
    if (stat.isDirectory()) {
      if (!IGNORE_DIRS.includes(entry)) {
        walkDir(fullPath, files);
      }
    } else if (stat.isFile()) {
      const ext = extname(entry);
      if (VALID_EXTENSIONS.includes(ext)) {
        files.push(fullPath);
      }
    }
  }
  return files;
}

function main() {
  const projectRoot = process.cwd();
  let totalFiles = 0;
  let modifiedFiles = 0;

  console.log(`Project root: ${projectRoot}`);
  console.log(`Searching for files...`);

  const files = walkDir(projectRoot);
  console.log(`Found ${files.length} files to check`);

  for (const file of files) {
    totalFiles++;
    try {
      const content = readFileSync(file, "utf-8");
      let newContent = content;
      let hasChanges = false;

      for (const [oldName, newName] of Object.entries(REPLACEMENTS)) {
        if (content.includes(oldName)) {
          newContent = newContent.split(oldName).join(newName);
          hasChanges = true;
        }
      }

      if (hasChanges) {
        writeFileSync(file, newContent, "utf-8");
        modifiedFiles++;
        console.log(`Modified: ${file.replace(projectRoot, ".")}`);
      }
    } catch (err) {
      console.error(`Error processing ${file}: ${err}`);
    }
  }

  console.log(`\nDone!`);
  console.log(`Total files scanned: ${totalFiles}`);
  console.log(`Files modified: ${modifiedFiles}`);
}

main();
