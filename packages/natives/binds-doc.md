# pi-natives 绑定架构文档

本文档详细介绍 `pi-natives` 的架构设计，包括进程管理、Shell 实现、原生工具链以及 TypeScript 与 Rust 的绑定机制。

---

## 目录

1. [packages/natives 包结构](#五packagesnatives-包结构)
2. [TypeScript 与 Rust 绑定原理](#六typescript-与-rust-绑定原理)

---


## 1、packages/natives 包结构

### 1.1 目录结构   

```
packages/natives/
├── native/
│   ├── index.js          # 原生模块加载器（核心）
│   ├── index.d.ts        # TypeScript 类型定义（napi-rs 生成）
│   ├── pi_natives.*.node # 编译后的原生二进制
│   └── embedded-addon.js # 嵌入式二进制引用（编译后生成）
├── scripts/
│   ├── build-native.ts   # 构建脚本
│   ├── embed-native.ts   # 嵌入二进制脚本
│   ├── gen-enums.ts      # 枚举导出生成
│   └── zig-safe-wrapper.ts # Zig 编译包装器
├── test/
│   └── native.test.ts    # 测试文件
├── bench/
│   └── grep.ts           # 性能基准测试
└── package.json
```

### 1.2 核心文件：native/index.js

#### 加载流程

```javascript
function loadNative() {
    const errors = [];

    // 1. 尝试从嵌入的二进制提取
    const embeddedCandidate = maybeExtractEmbeddedAddon(errors);

    // 2. 构建候选路径列表
    const runtimeCandidates = embeddedCandidate
        ? [embeddedCandidate, ...dedupedCandidates]
        : dedupedCandidates;

    // 3. 依次尝试加载
    for (const candidate of runtimeCandidates) {
        try {
            const bindings = require_(candidate);
            return bindings;  // 成功则返回
        } catch (err) {
            errors.push(`${candidate}: ${err.message}`);
        }
    }

    // 4. 全部失败，抛出详细错误
    throw new Error(`Failed to load pi_natives...\n${details}\n${helpMessage}`);
}
```

#### 路径解析优先级

```javascript
// x64 架构的候选文件（根据 AVX2 支持选择）
const addonFilenames = getAddonFilenames(platformTag, selectedVariant);
// 例如：["pi_natives.win32-x64-modern.node", "pi_natives.win32-x64-baseline.node"]

// 候选搜索路径
const baseReleaseCandidates = addonFilenames.flatMap(filename => [
    path.join(nativeDir, filename),   // ./native/pi_natives.*.node
    path.join(execDir, filename),      // 可执行文件目录
]);

const compiledCandidates = addonFilenames.flatMap(filename => [
    path.join(versionedDir, filename), // ~/.omp/natives/14.5.3/
    path.join(userDataDir, filename),  // ~/.local/bin/
]);
```

#### AVX2 检测（x64 CPU 变体）

```javascript
function detectAvx2Support() {
    if (process.arch !== "x64") return false;

    // Linux: 读取 /proc/cpuinfo
    if (process.platform === "linux") {
        const cpuInfo = fs.readFileSync("/proc/cpuinfo", "utf8");
        return /\bavx2\b/i.test(cpuInfo);
    }

    // macOS: sysctl
    if (process.platform === "darwin") {
        const leaf7 = runCommand("sysctl", ["-n", "machdep.cpu.leaf7_features"]);
        return /\bAVX2\b/i.test(leaf7);
    }

    // Windows: PowerShell
    if (process.platform === "win32") {
        const output = runCommand("powershell.exe", [...]);
        return output?.toLowerCase() === "true";
    }

    return false;
}

// 根据 AVX2 支持选择变体
function resolveCpuVariant(override) {
    if (process.arch !== "x64") return null;
    if (override) return override;
    return detectAvx2Support() ? "modern" : "baseline";
}
```

**变体区别**：

| 变体 | CPU 级别 | 说明 |
|------|---------|------|
| `modern` | x86-64-v3 | AVX2, FMA |
| `baseline` | x86-64-v2 | SSE4.2, CMPXCHG16B |
| `default` | native | 非 x64 平台 |

#### 嵌入式二进制处理

```javascript
function maybeExtractEmbeddedAddon(errors) {
    // 仅编译后的二进制模式
    if (!isCompiledBinary || !embeddedAddon) return null;

    // 版本/平台校验
    if (embeddedAddon.platformTag !== platformTag) return null;
    if (embeddedAddon.version !== packageVersion) return null;

    const selectedEmbeddedFile = selectEmbeddedAddonFile();
    const targetPath = path.join(versionedDir, selectedEmbeddedFile.filename);

    // 已存在则直接返回
    if (fs.existsSync(targetPath)) return targetPath;

    // 提取嵌入的二进制到磁盘
    const buffer = fs.readFileSync(selectedEmbeddedFile.filePath);
    fs.writeFileSync(targetPath, buffer);
    return targetPath;
}
```

### 1.3 构建脚本：scripts/build-native.ts

#### 构建流程

```typescript
async function main() {
    // 1. 确定构建参数
    const effectiveVariant = resolveEffectiveVariant(); // modern/baseline
    const profileLabel = useLocalProfile ? "local" : "ci";

    // 2. 设置 RUSTFLAGS（CPU 指令集）
    if (effectiveVariant === "modern") {
        Bun.env.RUSTFLAGS = "-C target-cpu=x86-64-v3";
    } else if (effectiveVariant === "baseline") {
        Bun.env.RUSTFLAGS = "-C target-cpu=x86-64-v2";
    }

    // 3. 调用 napi 构建
    const napiArgs = ["build", "--manifest-path", rustDir, ...];
    await $`${napiBin} ${napiArgs}`;

    // 4. 安装产物
    await installBinary(builtAddonPath, canonicalAddonPath);
    await installGeneratedBindings(buildOutputDir);

    // 5. 后处理
    await generateEnumExports();      // 生成枚举
    await patchGeneratedIndexLoader(); // 修补加载器
}
```

### 1.4 枚举生成：scripts/gen-enums.ts

napi-rs 生成的 `const enum` 在运行时没有值，需要手动导出：

```typescript
// 从 index.d.ts 解析 const enum
const CONST_ENUM_RE = /export declare const enum (\w+)\s*\{(.*?)\n\}/gs;

// 生成 JS 运行时导出
module.exports.AstMatchStrictness = {
    Cst: 'cst',
    Smart: 'smart',
    Ast: 'ast',
    Relaxed: 'relaxed',
    Signature: 'signature',
    Template: 'template',
};

// 同时修复 .d.ts：const enum -> enum
dtsContent = dtsContent.replaceAll("export const enum", "export declare enum");
```

### 1.5 测试覆盖

| 测试模块 | 测试内容 |
|---------|---------|
| `grep` | 模式匹配、glob 过滤、gitignore、FIFO 跳过 |
| `glob` | 文件匹配、类型过滤、缓存失效 |
| `fuzzyFind` | 模糊搜索 |
| `shell` | 超时、后台任务终止 |
| `pty` | PTY 会话超时 |
| `htmlToMarkdown` | HTML 转换 |
| `sanitizeText` | 文本清理 |
| `text tab width` | 制表符宽度 |

---

## 2、TypeScript 与 Rust 绑定原理

### 2.1 核心工具链

```
┌─────────────────────────────────────────────────────────────────┐
│                        napi-rs                                  │
├─────────────────────────────────────────────────────────────────┤
│  Rust 库 ──▶ N-API (Node API) ──▶ JavaScript 可调用模块        │
│                                                                 │
│  关键组件：                                                     │
│  • napi: Rust 端的 N-API 绑定库                                 │
│  • napi-derive: 过程宏，自动生成绑定代码                        │
│  • @napi-rs/cli: 构建工具，生成 .d.ts                           │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Rust 端：定义 API

```rust
// crates/pi-natives/src/shell.rs

use napi_derive::napi;  // 关键宏

/// 定义一个 JavaScript 可调用的类
#[napi]
pub struct Shell {
    session: Arc<TokioMutex<Option<ShellSessionCore>>>,
    abort_state: ShellAbortState,
    config: ShellConfig,
}

#[napi]
impl Shell {
    /// 构造函数
    #[napi(constructor)]
    pub fn new(options: Option<ShellOptions>) -> Self {
        // ...
    }

    /// 异步方法，返回 Promise
    #[napi]
    pub fn run<'e>(
        &self,
        env: &'e Env,
        options: ShellRunOptions<'e>,
        on_chunk: Option<ThreadsafeFunction<String>>,
    ) -> Result<PromiseRaw<'e, ShellRunResult>> {
        // ...
    }
}

/// 定义一个独立函数
#[napi]
pub fn kill_tree(pid: number, signal: number) -> number {
    // ...
}

/// 定义一个对象类型（用于参数/返回值）
#[napi(object)]
pub struct ShellRunOptions<'env> {
    pub command: String,
    pub cwd: Option<String>,
    pub env: Option<HashMap<String, String>>,
    pub timeout_ms: Option<u32>,
    pub signal: Option<Unknown<'env>>,
}
```

### 2.3 编译流程

```
┌────────────────┐     ┌────────────────┐     ┌────────────────┐
│  Rust 源码     │────▶│  napi-derive   │────▶│  .node 二进制  │
│  (#[napi] 宏)  │     │  (代码生成)    │     │  (动态库)      │
└────────────────┘     └────────────────┘     └────────────────┘
                                                      │
                         ┌────────────────────────────┘
                         ▼
┌────────────────┐     ┌────────────────┐
│  index.d.ts    │◀────│  @napi-rs/cli  │
│  (类型定义)    │     │  (自动生成)    │
└────────────────┘     └────────────────┘
```

### 2.4 自动生成的类型定义

Rust 代码：

```rust
#[napi(object)]
pub struct ShellRunResult {
    pub exit_code: Option<i32>,
    pub cancelled: bool,
    pub timed_out: bool,
    pub minimized: Option<MinimizerResult>,
}
```

生成的 `index.d.ts`：

```typescript
/** Result of running a shell command. */
export interface ShellRunResult {
  /** Exit code when the command completes normally. */
  exitCode?: number
  /** Whether the command was cancelled via abort. */
  cancelled: boolean
  /** Whether the command timed out before completion. */
  timedOut: boolean
  minimized?: MinimizerResult
}

/** Persistent brush-core shell session. */
export declare class Shell {
  constructor(options?: ShellOptions | undefined | null)
  run(options: ShellRunOptions, onChunk?: ...): Promise<ShellRunResult>
  abort(): Promise<void>
}
```

### 2.5 类型映射

| Rust 类型 | JavaScript 类型 |
|-----------|-----------------|
| `i32`, `u32` | `number` |
| `String` | `string` |
| `bool` | `boolean` |
| `Option<T>` | `T \| undefined \| null` |
| `Vec<T>` | `Array<T>` |
| `HashMap<K, V>` | `Record<K, V>` |
| `Result<T, E>` | 抛异常或返回 `T` |
| `Promise<T>` (async fn) | `Promise<T>` |

### 2.6 高级特性

#### 回调函数

```rust
// Rust 端
#[napi]
pub fn run(
    options: ShellRunOptions,
    #[napi(ts_arg_type = "(error: Error | null, chunk: string) => void")]
    on_chunk: Option<ThreadsafeFunction<String>>,
) -> Result<...> {
    // 从任意线程调用回调
    on_chunk.call(Ok(chunk), ThreadsafeFunctionCallMode::NonBlocking);
}
```

```typescript
// JavaScript 端
shell.run({ command: "ls" }, (err, chunk) => {
    console.log(chunk);
});
```

#### AbortSignal 支持

```rust
// Rust 端
#[napi]
pub fn run(
    options: ShellRunOptions,
    signal: Option<Unknown<'env>>,  // 接收 JS AbortSignal
) -> Result<...> {
    let ct = CancelToken::new(options.timeout_ms, signal);
    // ...
}
```

```typescript
// JavaScript 端
const controller = new AbortController();
shell.run({ command: "sleep 100", signal: controller.signal });
controller.abort();  // 取消
```

#### 枚举

```rust
// Rust 端
#[napi(string_enum)]  // 字符串枚举
pub enum GrepOutputMode {
    Content,
    Count,
    FilesWithMatches,
}
```

```typescript
// 生成的 .d.ts
export declare const enum GrepOutputMode {
    Content = 'content',
    Count = 'count',
    FilesWithMatches = 'filesWithMatches',
}
```

### 2.7 JavaScript 加载

```javascript
// native/index.js
const bindings = require_("./pi_natives.win32-x64-baseline.node");

// bindings 就是 Rust 导出的对象
// {
//   Shell: class Shell { ... },
//   grep: function grep() { ... },
//   killTree: function killTree() { ... },
//   GrepOutputMode: { Content: 'content', ... },
//   ...
// }

module.exports = bindings;
```

### 2.8 完整调用链

```
┌─────────────────────────────────────────────────────────────────┐
│  TypeScript                                                     │
│  import { Shell } from "@oh-my-pi/pi-natives";                  │
│  const shell = new Shell();                                     │
│  const result = await shell.run({ command: "ls" });             │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  JavaScript (native/index.js)                                   │
│  const bindings = require("./pi_natives.*.node");               │
│  bindings.Shell.run({ command: "ls" })                          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  N-API Bridge (V8 ↔ Rust)                                       │
│  V8 Isolate ──▶ napi_value ──▶ Rust 类型转换                   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Rust (crates/pi-natives/src/shell.rs)                          │
│  #[napi]                                                        │
│  impl Shell {                                                   │
│      pub fn run(&self, options: ShellRunOptions) -> ... {      │
│          // 真正的逻辑                                          │
│      }                                                          │
│  }                                                              │
└─────────────────────────────────────────────────────────────────┘
```

### 2.9 为什么用 napi-rs？

| 对比 | FFI (手动) | neon | napi-rs |
|------|-----------|------|---------|
| 类型安全 | ❌ 手动 | ⚠️ 部分 | ✅ 自动 |
| async/await | ❌ 手动 | ⚠️ 复杂 | ✅ 原生支持 |
| 跨平台 | ❌ 手动 | ⚠️ | ✅ |
| .d.ts 生成 | ❌ | ❌ | ✅ 自动 |
| 性能 | 高 | 高 | 高 |
| 维护成本 | 高 | 中 | 低 |

---

## 架构总览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           应用层 (TypeScript)                           │
├─────────────────────────────────────────────────────────────────────────┤
│  packages/natives/native/index.js  ◀──  加载 .node 二进制              │
│  packages/utils/src/procmgr.ts     ◀──  Shell 配置 + 进程终止          │
└─────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           绑定层 (N-API)                                │
├─────────────────────────────────────────────────────────────────────────┤
│  napi-rs: #[napi] 宏 ──▶ 自动生成 JS 可调用的 API                      │
│  类型映射、async/await、回调、AbortSignal 全自动                        │
└─────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           原生层 (Rust)                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  crates/pi-natives/                                                     │
│  ├── shell.rs      ◀── brush-core shell + 自定义 sleep/timeout        │
│  ├── grep.rs       ◀── ripgrep 引擎                                    │
│  ├── glob.rs       ◀── 文件系统遍历                                    │
│  ├── ast.rs        ◀── ast-grep 代码搜索                               │
│  ├── image.rs      ◀── 图片处理                                        │
│  ├── clipboard.rs  ◀── 剪贴板                                          │
│  └── ...                                                                │
└─────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           依赖层                                        │
├─────────────────────────────────────────────────────────────────────────┤
│  brush-core        ◀── Rust bash 解释器（可嵌入、可控制）              │
│  brush-builtins    ◀── bash 内置命令实现                               │
│  Git Bash 工具     ◀── Unix 外部命令 (ls/grep/sed...) [Windows]        │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 关键设计决策

| 决策 | 理由 |
|------|------|
| **brush 替代外部 bash** | 可编程控制、会话保持、优雅取消 |
| **原生实现工具** | 性能、可取消、流式输出、跨平台 |
| **CPU 变体 (modern/baseline)** | 兼容旧 CPU，利用新指令集加速 |
| **嵌入二进制模式** | 编译后单文件分发，无需外部依赖 |
| **napi-rs 绑定** | 类型安全、自动生成、维护成本低 |
