# ADR-001：使用 AppKit + SpriteKit

状态：已接受（首个里程碑）

## 决策

使用 AppKit 管理 `NSPanel`、菜单栏状态项、窗口层级、空间行为与非激活交互；使用 SpriteKit 组合矢量形状并驱动轻量 2D 待机动画。Swift Package Manager 负责无 Xcode 的构建，脚本组装标准 `.app` 包并执行纯逻辑检查。

## 理由

AppKit 直接暴露桌面宠物所需的非激活面板、透明窗口和鼠标穿透控制。SpriteKit 随系统提供，适合小型节点树、形状节点与确定时序动画，不增加依赖。纯几何与巡逻逻辑和 UI 分离；在当前仅有 Command Line Tools 的环境中由可返回失败码的独立逻辑检查程序验证，安装完整 Xcode 后再恢复标准 XCTest。

## 未采用方案

- SwiftUI：菜单很方便，但透明非激活浮窗、命中穿透和窗口层级最终仍需 AppKit 桥接，首版不会更小。
- Metal/OpenGL：对简单 2D 宠物过重。
- Web/Electron：体积与资源占用不符合轻量目标，且桌面窗口行为更间接。
- 第三方游戏引擎或动画库：引入不必要依赖，也违背离线、最小化里程碑范围。
