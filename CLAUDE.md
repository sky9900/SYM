# SYM 项目规则

## 构建、安装与运行

每次完成代码修改后，必须执行以下步骤：

1. 先关闭正在运行的 SYM app（如果有的话）
2. 使用 Release 配置编译项目
3. 将编译产物安装到 /Applications 目录
4. 启动应用

具体命令如下：

```bash
# 1. 关闭正在运行的 app
osascript -e 'tell application "SYM" to quit' 2>/dev/null; sleep 1

# 2. Release 编译
xcodebuild -project SYM.xcodeproj -scheme SYM -configuration Release build

# 3. 安装到 /Applications
rm -rf /Applications/SYM.app && cp -R ~/Library/Developer/Xcode/DerivedData/SYM-*/Build/Products/Release/SYM.app /Applications/

# 4. 启动应用
open /Applications/SYM.app
```

一行命令版本：

```bash
osascript -e 'tell application "SYM" to quit' 2>/dev/null; sleep 1 && xcodebuild -project SYM.xcodeproj -scheme SYM -configuration Release build && rm -rf /Applications/SYM.app && cp -R ~/Library/Developer/Xcode/DerivedData/SYM-*/Build/Products/Release/SYM.app /Applications/ && open /Applications/SYM.app
```
