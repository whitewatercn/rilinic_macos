# 鼠鬚管 (Squirrel) 构建与打包文档

## 概述

鼠鬚管是 Rime 输入法引擎的 macOS 版本。构建流程包括准备依赖、Xcode 编译、代码签名、
打包为 `.pkg` 安装包以及发布归档等步骤，全部通过 `Makefile` 编排。

## 项目结构速览

```
.
├── Makefile                  # 构建主控文件
├── Squirrel.xcodeproj/       # Xcode 项目
├── sources/                  # Swift 源代码
├── lib/                      # 编译后放置 librime 动态库与插件
│   ├── librime.1.dylib
│   └── rime-plugins/
├── bin/                      # 编译后放置 rime_deployer, rime_dict_manager 等工具
├── data/
│   └── opencc/              # OpenCC 简繁转换数据
├── Frameworks/               # Sparkle.framework
├── librime/                  # librime 源码与构建产物（通过 git submodule）
├── Sparkle/                  # Sparkle 自动更新框架（通过 git submodule）
├── package/                  # 打包脚本
│   ├── make_package          # 生成 .pkg 安装包
│   ├── sign_app              # 对 .app 进行代码签名
│   ├── make_archive          # 创建发布归档与 appcast
│   ├── add_data_files        # 动态注入资源文件到 Xcode 项目
│   ├── bump_version          # 更新版本号
│   ├── PackageInfo           # pkg 元信息
│   ├── Squirrel-component.plist  # 组件包描述
│   └── common.sh             # 公共函数
├── scripts/
│   └── postinstall           # 安装后脚本
└── resources/
    └── Squirrel.entitlements # 沙箱权限配置
```

## 环境要求

| 依赖         | 说明                                                               |
| ------------ | ------------------------------------------------------------------ |
| macOS 13.0+  | 最低系统版本                                                       |
| Xcode        | 含命令行工具 (`xcode-select --install`)                            |
| git          | 用于 submodule 管理                                                |

## 构建前准备

### 克隆仓库并初始化子模块

```bash
git clone --recursive https://github.com/rime/squirrel.git
cd squirrel
```

如果已克隆但未拉取子模块：

```bash
git submodule update --init --recursive
```

## Makefile 目标说明

| 目标                | 说明                                                               |
| ------------------- | ------------------------------------------------------------------ |
| `make` 或 `make release` | 构建 Release 版 `.app`（默认目标）                             |
| `make debug`        | 构建 Debug 版 `.app`                                               |
| `make deps`         | 构建所有依赖（librime + OpenCC 数据）                              |
| `make librime`      | 仅构建 librime 及其依赖                                            |
| `make data`         | 仅构建 OpenCC 数据                                                 |
| `make package`      | 构建 Release 版并打包为 `.pkg`                                     |
| `make archive`      | 打包并生成发布归档与 Sparkle appcast                                |
| `make install-release` | 构建 Release 并安装到 `/Library/Input Methods`                   |
| `make install-debug` | 构建 Debug 并安装到 `/Library/Input Methods`                      |
| `make clean`        | 清理构建产物                                                       |
| `make clean-deps`   | 清理依赖构建产物                                                   |
| `make clean-package` | 清理打包产物                                                      |

### 常用构建参数

```bash
# 指定 CPU 架构（默认 universal x86_64 + arm64）
make release ARCHS="arm64"

# 指定最低系统版本
make release MACOSX_DEPLOYMENT_TARGET=13.0

# 使用 Developer ID 签名（正式发布必须）
make package DEV_ID="Your Developer ID"
```

## 完整构建流程

### 第一步：准备依赖

#### 方式一：从源码编译依赖（开发环境）

```bash
make deps
```

这一步会依次执行：

1. **编译 librime**：调用 `librime/Makefile`，编译 C++ 核心库
2. **复制 librime 产物**：
   - `librime.1.dylib` → `lib/`
   - `rime-plugins/` → `lib/rime-plugins/`
   - `rime_deployer`、`rime_dict_manager` → `bin/`
   - 使用 `install_name_tool` 为二进制设置 rpath 为 `@loader_path/../Frameworks`
3. **复制 OpenCC 数据**：简繁转换词典 → `data/opencc/`

#### 方式二：使用预编译依赖（CI / 快速构建）

运行 `action-install.sh`，从 GitHub Release 下载预编译的 universal 二进制：

- **librime**：`rime-<hash>-macOS-universal.tar.bz2`
- **rime-deps**：`rime-deps-<hash>-macOS-universal.tar.bz2`
- **Sparkle**：`Sparkle-<version>.tar.xz`

```bash
./action-install.sh
```

### 第二步：编译 Squirrel.app

```bash
make release
```

等价于：

```bash
# 1. 动态注入 Rime 插件到 Xcode 项目
bash package/add_data_files

# 2. Xcode 命令行构建
xcodebuild \
  -project Squirrel.xcodeproj \
  -configuration Release \
  -scheme Squirrel \
  -derivedDataPath build \
  build
```

**`add_data_files` 的作用**：将 `lib/rime-plugins/` 下的插件动态库自动注册到 Xcode 项目文件 (`project.pbxproj`) 中，
确保它们在 Xcode 的 Copy Files Phase 被复制到 `.app` 包内。

构建产物位于：

```
build/Build/Products/Release/Squirrel.app/
├── Contents/
│   ├── MacOS/
│   │   ├── Squirrel          # 主程序
│   │   ├── rime_deployer     # Rime 部署工具
│   │   └── rime_dict_manager # Rime 词典管理工具
│   ├── Frameworks/
│   │   └── Sparkle.framework # 自动更新框架
│   ├── Resources/
│   └── SharedSupport/        # 内置共享数据
│       └── ...
```

### 第三步：代码签名（正式发布）

仅当设置了 `DEV_ID` 环境变量时执行：

```bash
codesign --deep --force --options runtime --timestamp \
  --sign "Developer ID Application: ${DEV_ID}" \
  --entitlements resources/Squirrel.entitlements \
  --verbose "build/Build/Products/Release/Squirrel.app"

spctl -a -vv "build/Build/Products/Release/Squirrel.app"
```

- `--deep`：递归签名所有嵌套 bundle
- `--options runtime`：启用 Hardened Runtime
- `--timestamp`：附加时间戳
- `--entitlements`：应用沙箱权限配置

### 第四步：打包为 .pkg 安装包

```bash
make package
```

等价于：

```bash
# 1. 代码签名 .app（可选，需 DEV_ID）
bash package/sign_app "${DEV_ID}" "${DERIVED_DATA_PATH}"

# 2. 使用 pkgbuild 打包
bash package/make_package "${DERIVED_DATA_PATH}"
```

`pkgbuild` 调用：

```bash
pkgbuild \
    --info PackageInfo \
    --root "build/Build/Products/Release" \
    --filter '.*\.swiftmodule$' \
    --component-plist Squirrel-component.plist \
    --identifier 'im.rime.inputmethod.Squirrel' \
    --version "<版本号>" \
    --install-location '/Library/Input Methods' \
    --scripts scripts \
    Squirrel.pkg
```

| 参数                 | 含义                                                              |
| -------------------- | ----------------------------------------------------------------- |
| `--root`             | 打包内容根目录（即 Xcode 构建产物）                                |
| `--filter`           | 排除 `.swiftmodule` 文件                                          |
| `--install-location` | 目标安装路径 `/Library/Input Methods`（macOS 输入法标准路径）      |
| `--scripts`          | 安装脚本目录，包含 `postinstall`                                   |
| `--component-plist`  | 组件描述文件，定义 bundle 关系与升级策略                           |
| `--identifier`       | 包标识符 `im.rime.inputmethod.Squirrel`                           |

#### PackageInfo

```xml
<pkg-info postinstall-action="logout"/>
```

`postinstall-action="logout"` 表示安装后需要重新登录才能生效。

#### Squirrel-component.plist

描述包内的 bundle 结构：

```
Squirrel.app                                    # 主应用
  └── Contents/Frameworks/Sparkle.framework     # 子组件
```

- `BundleIsRelocatable: false`：不允许用户移动
- `BundleOverwriteAction: upgrade`：安装时覆盖旧版

### 第五步：二次签名与公证（正式发布）

```bash
# 对 .pkg 进行二次签名
productsign --sign "Developer ID Installer: ${DEV_ID}" \
  package/Squirrel.pkg \
  package/Squirrel-signed.pkg

# 替换原始包
rm package/Squirrel.pkg
mv package/Squirrel-signed.pkg package/Squirrel.pkg

# 提交 Apple 公证
xcrun notarytool submit package/Squirrel.pkg \
  --keychain-profile "${DEV_ID}" --wait

# 装订公证凭证到包中
xcrun stapler staple package/Squirrel.pkg
```

### 第六步：创建发布归档

```bash
make archive
```

生成以下产物：

| 文件                          | 说明                               |
| ----------------------------- | ---------------------------------- |
| `package/Squirrel-{版本}.pkg` | 带版本号的安装包                   |
| `package/appcast.xml`         | 正式更新频道                       |
| `package/testing-appcast.xml` | 测试更新频道                       |
| `package/debug-appcast.xml`   | 本地测试频道                       |

`appcast.xml` 是基于 [Sparkle](https://sparkle-project.org/) 规范的 RSS 更新信息文件，
包含版本号、最小系统版本、EdDSA 签名、下载地址等。

## 安装流程（从 .pkg）

双击 `.pkg` 安装包后，系统会：

1. 将 `Squirrel.app` 安装到 `/Library/Input Methods/`
2. 执行 `scripts/postinstall` 脚本：
   - 杀掉当前运行的 Squirrel 进程
   - 注册输入法：`Squirrel --register-input-source`
   - 预编译 Rime 配置：`Squirrel --build`
   - 为当前用户启用并切换到该输入法

词库和配置文件更新由应用内「医键通」入口管理。该入口登录后从云端 OSS 获取 `rilinic/`
文件列表，下载选中的文件，并部署到当前用户的 `~/Library/Rime`。

## 本地开发安装

```bash
# Release 版安装
make install-release

# Debug 版安装
make install-debug
```

直接将编译好的 `.app` 复制到 `/Library/Input Methods/`，并执行 `postinstall`，
跳过打包步骤，适合开发调试。

## CI 构建

项目中的 `action-build.sh` 是 CI 的入口脚本：

```bash
./action-build.sh release   # 构建 release 版
./action-build.sh debug     # 构建 debug 版
```

它依次调用 `action-install.sh`（下载预编译依赖）和 `make <target>` 完成构建。
