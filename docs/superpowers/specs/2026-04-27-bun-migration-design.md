# Bun 迁移设计文档

**日期**: 2026-04-27
**分支**: feat/bun-migration
**状态**: 待实施

## 概述

将 pi-mono 从 Node.js/npm 运行时迁移到 Bun，采用源码直接运行模式（不编译 TypeScript）。

## 目标

- 使用 Bun 作为运行时和包管理器
- 源码直接运行，移除编译步骤
- 重命名包为 `@runope/pi-*`
- 保持与上游同步的能力

## 关键决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 包名前缀 | `@runope/pi-*` | 公开发布需要独立身份 |
| 配置目录 | `.pi/`（保留） | 减少改动，方便合并上游 |
| 运行模式 | 源码直接运行 | 开发体验最佳，参考 oh-my-pi |
| 包管理器 | Bun 1.3+ | 原生支持 TypeScript |
| 原生模块 | 后续添加 | 先完成核心迁移 |

## 迁移范围

### 核心包（7 个）

| 包名 | 新包名 | 说明 |
|------|--------|------|
| `@mariozechner/pi-ai` | `@runope/pi-ai` | LLM 提供商抽象 |
| `@mariozechner/pi-agent-core` | `@runope/pi-agent-core` | Agent 运行时 |
| `@mariozechner/pi-coding-agent` | `@runope/pi-coding-agent` | CLI 入口 |
| `@mariozechner/pi-tui` | `@runope/pi-tui` | 终端 UI |
| `@mariozechner/pi-web-ui` | `@runope/pi-web-ui` | Web 组件 |
| `@mariozechner/pi-mom` | `@runope/pi-mom` | Slack 机器人 |
| `@mariozechner/pi-pods` | `@runope/pi-pods` | GPU pods 管理 |

### 新增包（后续）

- `@runope/pi-natives` - Rust 原生模块（参考 oh-my-pi）

## 实施阶段

### Phase 1: 基础设施迁移

**根 package.json 改动**:
```json
{
  "packageManager": "bun@1.3.12",
  "workspaces": {
    "packages": ["packages/*"],
    "catalog": { ... }
  }
}
```

**新增文件**:
- `bunfig.toml` - Bun 配置
- 更新 `tsconfig.json` 适配 Bun

**移除**:
- `package-lock.json`
- `node_modules/`

### Phase 2: 包迁移

每个包的 `package.json` 改动：

```json
{
  "name": "@runope/pi-ai",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "exports": {
    ".": {
      "types": "./src/index.ts",
      "import": "./src/index.ts"
    }
  },
  "engines": {
    "bun": ">=1.3.7"
  },
  "scripts": {
    "check": "biome check . && bun run check:types",
    "check:types": "tsgo -p tsconfig.json --noEmit"
  }
}
```

**依赖引用更新**:
- 所有 `@mariozechner/pi-*` → `@runope/pi-*`
- 使用 `catalog:` 引用 workspace 依赖

### Phase 3: CLI 入口

`packages/coding-agent/package.json`:
```json
{
  "bin": {
    "pi": "./src/cli.ts"
  }
}
```

### Phase 4: 测试验证

1. `bun install` - 安装依赖
2. `bun run check` - 代码检查
3. `bun test` - 运行测试
4. `bun packages/coding-agent/src/cli.ts --version` - CLI 测试

### Phase 5: CI/CD

更新 `.github/workflows/`:
- 使用 `oven-sh/setup-bun` action
- 替换 npm 命令为 bun 命令

## 文件变更清单

### 修改文件

| 文件 | 改动 |
|------|------|
| `package.json` | packageManager, workspaces, scripts |
| `packages/*/package.json` | name, main, types, exports, scripts, engines |
| `tsconfig.json` | Bun 适配 |
| `.github/workflows/*.yml` | 使用 Bun |
| `AGENTS.md` | 更新命令为 bun |

### 新增文件

| 文件 | 说明 |
|------|------|
| `bunfig.toml` | Bun 配置 |
| `docs/superpowers/specs/2026-04-27-bun-migration-design.md` | 本文档 |

### 删除文件

| 文件 | 说明 |
|------|------|
| `package-lock.json` | npm 锁文件 |
| `packages/*/dist/` | 编译产物 |

## 风险与缓解

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| Node.js API 不兼容 | 低 | 中 | Bun 高度兼容 Node.js |
| 依赖不支持 Bun | 中 | 高 | 检查依赖兼容性，寻找替代 |
| 原生模块问题 | 中 | 中 | 使用 napi-rs（Bun 兼容） |
| 合并上游冲突 | 高 | 低 | 脚本处理包名替换 |

## 参考项目

- [oh-my-pi](https://github.com/can1357/oh-my-pi) - Bun + 源码直接运行参考
- [GSD-2](https://github.com/gsd-build/GSD-2) - Node.js + 编译模式参考

## 成功标准

- [ ] `bun install` 成功
- [ ] `bun run check` 无错误
- [ ] 测试通过
- [ ] CLI 可运行
- [ ] 可发布到 npm

## 后续工作

1. 添加原生模块 `@runope/pi-natives`
2. 添加自定义扩展
3. 设置 CI/CD 发布流程
