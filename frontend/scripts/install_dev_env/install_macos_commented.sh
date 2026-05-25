#!/usr/bin/env bash
# 这是一个bash脚本的声明行，告诉系统使用bash解释器来执行这个脚本
# /usr/bin/env 是一种更灵活的方式，它会在系统的PATH中查找bash

# ============================================================
# 颜色定义部分 - 用于在终端输出彩色文字
# ============================================================
YELLOW="\e[93m"    # 定义黄色，ANSI转义码：\e[93m 表示明亮的黄色
GREEN="\e[32m"     # 定义绿色，ANSI转义码：\e[32m 表示绿色
RED="\e[31m"       # 定义红色，ANSI转义码：\e[31m 表示红色
ENDCOLOR="\e[0m"   # 重置颜色，\e[0m 表示恢复到默认颜色，防止颜色影响后续输出

# ============================================================
# 工具函数定义 - 用于在终端输出不同颜色的消息
# ============================================================

# 打印普通消息（黄色）
printMessage() {
   # printf 是格式化输出命令
   # ${YELLOW} 应用黄色，$1 是函数的第一个参数（要输出的消息），${ENDCOLOR} 重置颜色，\n 换行
   printf "${YELLOW}AppFlowy : $1${ENDCOLOR}\n"
}

# 打印成功消息（绿色）
printSuccess() {
   # 和上面类似，但使用绿色
   printf "${GREEN}AppFlowy : $1${ENDCOLOR}\n"
}

# 打印错误消息（红色）
printError() {
   # 和上面类似，但使用红色
   printf "${RED}AppFlowy : $1${ENDCOLOR}\n"
}

# ============================================================
# 第一步：安装 Rust 编程语言
# ============================================================
# Install Rust
printMessage "The Rust programming language is required to compile AppFlowy."
# 提示用户：Rust编程语言是编译AppFlowy所必需的

printMessage "We can install it now if you don't already have it on your system."
# 提示用户：如果系统中还没有Rust，现在可以安装它

# read 命令用于读取用户输入
# -p 参数表示先显示提示信息
# $(printSuccess "...") 会先执行printSuccess函数，显示绿色的提示
# 用户的输入会被保存到变量 installrust 中
read -p "$(printSuccess "Do you want to install Rust? [y/N]") " installrust

# 判断用户是否选择安装Rust
# ${installrust:-N} 表示：如果installrust变量为空，则使用默认值N
# [Yy] 是一个模式，匹配Y或y
if [[ "${installrust:-N}" == [Yy] ]]; then
   # 如果用户输入Y或y，执行安装
   printMessage "Installing Rust."
   
   # 使用Homebrew（macOS的包管理器）安装rustup-init
   # rustup-init是Rust的安装和版本管理工具
   brew install rustup-init
   
   # 运行rustup-init来实际安装Rust
   # -y 表示自动同意所有提示（非交互式安装）
   # --default-toolchain=stable 表示安装stable（稳定版）工具链
   rustup-init -y --default-toolchain=stable

   # source命令用于在当前shell中执行脚本
   # $HOME是用户的主目录（如：/Users/kuncao）
   # .cargo/env 包含了Rust相关的环境变量设置（如PATH路径）
   # 这样就可以立即使用cargo、rustc等命令，而不需要重启终端
   source "$HOME/.cargo/env"
else
   # 如果用户选择N或直接回车（默认值），跳过安装
   printMessage "Skipping Rust installation."
fi

# ============================================================
# 第二步：安装 SQLite3 数据库
# ============================================================
# Install sqllite
printMessage "Installing sqlLite3."
# 使用Homebrew安装sqlite3数据库
# SQLite是一个轻量级的嵌入式数据库，AppFlowy用它来存储本地数据
brew install sqlite3

# ============================================================
# 第三步：设置 Flutter 开发环境
# ============================================================
printMessage "Setting up Flutter"

# Get the current Flutter version
# 获取当前安装的Flutter版本号
# flutter --version 输出Flutter版本信息
# | 是管道符，将前一个命令的输出传递给下一个命令
# grep -oE 'Flutter [^ ]+' 使用正则表达式提取"Flutter"后面的版本号部分
# 第二个grep -oE '[^ ]+$' 提取最后一个不包含空格的字符串（版本号）
FLUTTER_VERSION=$(flutter --version | grep -oE 'Flutter [^ ]+' | grep -oE '[^ ]+$')

# Check if the current version is 3.27.4
# 检查当前Flutter版本是否已经是3.27.4
if [ "$FLUTTER_VERSION" = "3.27.4" ]; then
   # 如果已经是3.27.4，直接提示，不需要切换
   echo "Flutter version is already 3.27.4"
else
   # 如果不是3.27.4，需要切换版本
   # Get the path to the Flutter SDK
   
   # which flutter 命令返回flutter命令的完整路径（如：/Users/xxx/flutter/bin/flutter）
   FLUTTER_PATH=$(which flutter)
   
   # ${FLUTTER_PATH%/bin/flutter} 是bash的字符串操作
   # % 表示从右边删除最短匹配
   # 这里删除了 /bin/flutter 部分，得到Flutter SDK的根目录
   FLUTTER_PATH=${FLUTTER_PATH%/bin/flutter}

   # pwd 命令返回当前工作目录
   # 先保存当前目录，以便后面切换回来
   current_dir=$(pwd)

   # 切换到Flutter SDK目录
   # $FLUTTER_PATH 前面没有引号，所以空格会被当作分隔符（这里应该加引号更安全）
   cd $FLUTTER_PATH
   
   # Use git to checkout version 3.27.4 of Flutter
   # Flutter SDK是用git管理的，使用git checkout切换到3.27.4这个tag/分支
   # 这样可以确保所有开发者使用相同版本的Flutter，避免兼容性问题
   git checkout 3.27.4
   
   # Get back to current working directory
   # 切换回之前保存的目录
   cd "$current_dir"

   echo "Switched to Flutter version 3.27.4"
fi

# Enable linux desktop
# 这个注释写错了，应该是"Enable macOS desktop"
# 启用Flutter的macOS桌面支持
# 默认情况下Flutter只支持移动端（iOS/Android），这个命令启用桌面应用开发
flutter config --enable-macos-desktop

# Fix any problems reported by flutter doctor
# 运行flutter doctor命令
# flutter doctor会检查Flutter开发环境的完整性，包括：
# - Flutter SDK是否正确安装
# - Dart SDK是否可用
# - 必要的工具是否安装（如Xcode、Android Studio等）
# - 是否有任何配置问题
# 它会输出一个报告，告诉你哪些是正常的✓，哪些有问题✗
flutter doctor

# ============================================================
# 第四步：设置 Git Hooks
# ============================================================
# Add the githooks directory to your git configuration
printMessage "Setting up githooks."

# Git hooks是Git的钩子机制，可以在特定的Git操作时自动执行脚本
# 比如在提交代码前自动检查代码格式、运行测试等
# 这个命令告诉Git使用项目中的.githooks目录，而不是默认的.git/hooks目录
# core.hooksPath 是Git的配置项，指定hooks脚本的位置
git config core.hooksPath .githooks

# ============================================================
# 第五步：安装 go-gitlint（Git提交信息检查工具）
# ============================================================
# Install go-gitlint
printMessage "Installing go-gitlint."

# 定义要下载的文件名
# go-gitlint是一个用Go语言编写的工具，用于检查Git提交信息的格式是否符合规范
GOLINT_FILENAME="go-gitlint_1.1.0_osx_x86_64.tar.gz"

# 使用curl命令从GitHub下载go-gitlint
# -L 参数表示如果有重定向，跟随重定向
# --output 指定下载后保存的文件名
curl -L https://github.com/llorllale/go-gitlint/releases/download/1.1.0/${GOLINT_FILENAME} --output ${GOLINT_FILENAME}

# 解压下载的tar.gz文件
# tar 是Linux/macOS的打包压缩工具
# -z 表示使用gzip解压
# -x 表示解压（extract）
# -v 表示显示详细信息（verbose）
# --directory .githooks/. 指定解压到.githooks目录
# -f 指定要解压的文件
# gitlint 是要提取的文件名（只提取这一个文件，不是全部）
tar -zxv --directory .githooks/. -f ${GOLINT_FILENAME} gitlint

# 删除下载的压缩包文件，因为已经解压完成，不再需要
rm ${GOLINT_FILENAME}

# ============================================================
# 第六步：进入frontend目录，安装Rust相关工具
# ============================================================
# Change to the frontend directory
# 切换到frontend目录
# || exit 1 表示：如果cd命令失败（目录不存在），则退出脚本，返回错误码1
cd frontend || exit 1

# Install cargo make
printMessage "Installing cargo-make."
# cargo是Rust的包管理器和构建工具
# cargo install 用于安装Rust工具
# --force 表示如果已经安装过，则强制重新安装（覆盖旧版本）
# cargo-make 是一个任务运行器，类似于Makefile，但专为Rust项目设计
# 它可以定义和运行复杂的构建任务
cargo install --force cargo-make

# Install duckscript
printMessage "Installing duckscript."
# 安装duckscript_cli
# --locked 表示使用Cargo.lock文件中指定的精确版本，确保依赖版本一致
# duckscript是一种简单的脚本语言，cargo-make可以在任务中使用它
cargo install --force --locked duckscript_cli

# ============================================================
# 第七步：检查所有前置条件
# ============================================================
# Check prerequisites
printMessage "Checking prerequisites."
# 运行cargo-make任务
# appflowy-flutter-deps-tools 是在Makefile.toml中定义的一个任务
# 这个任务会检查AppFlowy Flutter开发所需的所有依赖工具是否正确安装
cargo make appflowy-flutter-deps-tools


# ============================================================
# 脚本功能总结
# ============================================================
# 
# 这个脚本是AppFlowy项目的macOS开发环境自动化安装脚本，主要完成以下任务：
#
# 1. **Rust环境安装**（可选）
#    - 询问用户是否需要安装Rust
#    - 通过rustup-init安装Rust稳定版
#    - 配置Rust环境变量
#
# 2. **SQLite3数据库安装**
#    - 安装SQLite3，AppFlowy用它存储本地数据
#
# 3. **Flutter环境配置**
#    - 检查Flutter版本，如果不是3.27.4则自动切换
#    - 启用macOS桌面应用支持
#    - 运行flutter doctor检查环境
#
# 4. **Git开发工作流配置**
#    - 配置Git Hooks路径
#    - 下载并安装go-gitlint工具（用于检查提交信息规范）
#
# 5. **Rust构建工具安装**
#    - 安装cargo-make（任务运行器）
#    - 安装duckscript（脚本语言支持）
#
# 6. **依赖检查**
#    - 运行预定义的检查任务，验证所有依赖工具是否正确安装
#
# 使用场景：
# - 新开发者首次搭建AppFlowy开发环境
# - 重置或更新现有开发环境
# - 确保团队成员使用统一的工具版本
#
# 注意事项：
# - 需要预先安装Homebrew（macOS包管理器）
# - 需要预先安装Flutter SDK
# - 需要有网络连接（下载依赖）
# - 脚本需要在AppFlowy项目根目录执行

