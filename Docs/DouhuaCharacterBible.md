# 豆花角色小圣经

## 视觉身份

豆花是一只英短金渐层。核心辨识点是圆脸、巨大的绿色眼睛与深色眼线、粉色鼻头、浅色口鼻/下巴/胸口；被毛整体温暖金色，头顶和背部更深。身体紧凑丰润，腿短而结实，尾巴粗厚且尾尖颜色深。

## 行为语言

常见姿态包括香箱、侧躺、翻肚皮；活动时会慢速追踪目标、嗅闻，并与人的手互动。总体是休息主导、短时间活跃爆发的低打扰节奏，而非持续高能奔跑。

现有视频缺少干净、无遮挡的完整步态循环，不能据此可靠制作行走动画。0.5 不再让休息姿势横向滑行；豆花停在屏幕一处，保留真实呼吸、眼神、转头、耳朵和尾巴微动。

## v1.0 写实模型表与精灵归档

2026-07-11 已依据主人提供的真实照片生成并接入 `v1.0-realistic`：

- 模型表：`Docs/Art/douhua-model-sheet-v1.0-realistic.png`
- 精灵归档：`Docs/Art/AnimationSource/archive/static-assets-retired/Douhua/v1.0-realistic/`
- 状态：慢走、观察、香箱、侧卧睡眠、摸头反应
- 合同：480×440 RGBA 制作资源，对应默认 240×220 pt 显示，共同缩放与基线

这套资源现已归档，不是当前运行基线。新增动作若导致脸、身体、毛纹或尾巴在时间上漂移，应拒绝接入。

原始照片和原始视频不进入应用包。当前运行基线是去背景、去声音、固定裁切后的派生 HEVC 透明片段，制作链为 `Scripts/BuildLiveVideoAssets.swift` 与 `Scripts/build-live-video.sh`。

## v0.2 历史 PoC

仓库归档目录仍保留第一版 `v0.2-offline` 作为历史技术 PoC：

- 模型表：`Docs/Art/douhua-model-sheet-v0.2-offline.png`
- 精灵归档：`Docs/Art/AnimationSource/archive/static-assets-retired/Douhua/v0.2/`

这套资产由 `Scripts/GenerateDouhuaAssets.swift` 使用 AppKit/CoreGraphics 离线确定性生成。它只是临时矢量/栅格 fallback，不再作为运行时主资源。

替换或扩展 v1 资源时必须继续通过 `Docs/Art/DouhuaRealisticArtBrief-v1.md` 的身份与风格审核，并更新版本化 manifest。
