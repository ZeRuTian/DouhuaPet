# 豆花 3D 生成执行记录

日期：2026-07-13

## 已完成

- 根据真实豆花参考板生成纯侧向中性站立锚点，已去背景：`Docs/Art/3D/identity-anchors/douhua-side-stand-anchor-v1.png`。
- App 已接入 SceneKit `SK3DNode` 与标准猫科骨骼驱动层。
- 已实现观察呼吸、四拍慢步、香箱、睡眠、摸头、耳动和尾巴程序化姿态。
- 已实现 USDZ 根节点、骨骼、网格、蒙皮和材质校验脚本。
- 正式模型不存在时，App 会回退到已防抖真实视频。

## 已尝试的生成服务

### Microsoft TRELLIS.2 公开 Space

- 预处理：成功。
- 512³ 形体与材质生成：成功。
- GLB 提取：失败，Hugging Face ZeroGPU 匿名日配额在提取阶段用尽。
- 结果：未导出候选网格，未向 App 接入半成品。

### Stability AI Stable Fast 3D 公开 Space

- 透明与白底输入均返回上游未公开异常。
- 结果：未导出候选网格。

## 本机条件

- Apple M5 Pro，48 GB 统一内存，Metal 4。
- Stable Fast 3D 官方说明其 MPS 为实验性，32 GB 以上机器可尝试 MPS；本机容量满足，但模型权重为 Hugging Face gated model。
- 本机尚未安装 Blender；正式重拓扑、骨架修正、自动权重和 USD 导出需要 Blender 或等价 DCC。

## 下一步所需外部条件

1. 在 Hugging Face 接受 Stable Fast 3D 模型许可，并在本机执行 `hf auth login`；不应在文档或对话中粘贴 token。
2. 选择本地 MPS 生成（隐私最好）或一次性 24 GB+ NVIDIA 云端任务（速度更快）。
3. 获得 GLB 后先做六视图身份验收；通过后才安装/使用 Blender 做重拓扑和绑定。
4. 导出 `douhua_rigged.usdz`，运行 `Scripts/ValidateDouhuaRig.swift`，通过后放入 App 资源。
