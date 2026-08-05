# 豆花像素动画 Demo

这是与当前写实版并存的独立风格验证，不会覆盖 `DouhuaPet.app`。

## v2 校正

- 桌面显示由 `384×288` 缩小为 `320×240`，像素纹理仍保持整数倍缩放。
- 躯干和腹部比 v1 收窄，减少桶状感；增加可见腿长和爪子分离度。
- 毛色从偏橙改为更接近参考照的金棕/灰棕渐层，并加长粗尾巴。
- 从 `192×144` 资源画布调整为 `160×120`，在 App 中正好以 2倍显示。

## v4 半尺寸与无穿模步态

- App 窗口和角色从 `320×240` 再缩小一倍为 `160×120`。
- 重绘严格侧视步态，远侧腿不再以深色块穿过近侧腿。
- 生成后由 `clean-pixel-demo-limbs.py` 逐帧去除残留的远侧爪子，保留一条清晰前腿和一条清晰后腿。
- 走路速度从 46 点/秒降到 32 点/秒，与半尺寸角色匹配。

## 录屏问题修正（v0.4）

- 录屏显示真正的主要问题是“状态边界穿模”：静止素材躯干直立，行走素材低身前伸，开始/停止时整个头背腹跳变。
- 静止与行走现在共用第 6 号落脚锚点帧；不再通过换整张图表现眨眼。
- 减速停下后不会立即切图，而是继续到下一个落脚相位再冻结。
- 分格后只保留最大 alpha 连通主体，清除录屏中间歇出现的边缘残片。
- 四张行走图按头部/躯干重新登记到同一水平坐标，消除素材在窗口内部最多约 12 个源像素的横向漂移。
- 窗口和角色由 `160×120` 再精确缩小一倍为 `80×60`；在 Retina 屏幕上正好对应 `160×120` 源纹理，避免非整数采样。
- 行走速度同比降为 16 点/秒。

## 四腿解剖修正（v0.5）

- v0.4 为规避穿模而完全删除远侧腿，导致 80×60 实机中只剩一条前腿和一条后腿；这是过度修正。
- v0.5 重新生成完整四腿素材：近侧前/后腿完整显示，远侧前/后腿使用略深毛色并水平错开，四只爪子均可辨认。
- `finalize-pixel-demo-v5.py` 只清除分格边缘碎片和校正身体登记点，明确不删除任何腿。
- 额外预留 28 个源像素的水平安全边距，使四腿步态对齐后仍不会碰到窗口边缘。

## 跨格轮廓修正（v0.6）

- 新录屏显示部分脸部边缘和伸出的前爪仍会变成垂直截断；根因不是 App 窗口，而是生成图中的主体跨过了固定四等分格线。
- `prepare-pixel-demo-sprites.py --component-split` 现在先在整张透明图中识别八个完整猫主体，再按主体连通轮廓分帧，不再硬切 `4×2` 数学边界。
- 跨格的脸颊、胡须根部和前爪被完整取回，同时仍保留 `28` 源像素安全边距。
- 重新测量后四张行走帧的上半身登记只需 `-2/0/0/0` 像素校正，避免旧偏移把完整轮廓推离画布。

## 真实节奏动作系统（v0.7）

- 根据豆花真实素材重新设计了八帧慢走、八帧短跑、起跳/落地和抬爪对话姿态，不再用同一组图硬套所有行为。
- 步态相位由窗口在屏幕上的实际位移驱动：慢走每 `22 pt` 完成一个周期，短跑每 `34 pt` 完成一个周期；加减速时腿频同步改变。
- 走、跑和停止的转场等待植足相位，避免前爪在空中时突然切换姿态。
- 跳跃由预压、蹬地、腾空、落地组成，位移是约 `0.78 s / 26 pt` 的平滑抛物线。
- 新增独立对话气泡窗口和“发现→抬头→抬爪→保持”互动；点击豆花会触发回应。
- 自动演示以 `7.5–14 s` 的安静观察为主，短跑只是低概率爆发，不再持续高频动作。

v0.7 的动作设计、生成提示词与质检联络表位于 `Docs/Art/PixelDemo/v7-actions/`。

## 真实身材统一（v0.8）

- 从真实照片和视频重新建立四视图比例模型，锁定圆头、宽胸腔、紧凑躯干、饱满髋部、短而结实的腿和中等粗尾巴。
- 肩到臀的核心躯干约为 `1.6–1.75 个头宽`，可见下肢约为 `0.5–0.6 个头高`；不再使用 v0.7 偏长的躯干和偏高的腿。
- 八帧闲置、八帧慢走、八帧短跑和八帧跳跃/对话均以同一张标准体型图为生成输入。
- 闲置组额外按对话站姿的肩高缩放校准，避免从静止到行走时整只猫突然变大。
- 闲置改为约 `6.25 s` 的慢呼吸、闭眼和睁眼循环，取消程序化拉伸整只猫的呼吸效果。

v0.8 的比例规范、参考联络表、提示词和质检图位于 `Docs/Art/PixelDemo/v8-proportions/`。

## 动作身份锁与固定像素尺度（v0.8.1）

- 将最终运行时闲置首帧设为唯一身份母版，不再让短跑或跳跃动作自行解释豆花的头脸和身材。
- 完整重做八帧短跑，并把四帧跳跃扩充为八帧渐进姿态；第一帧和末帧都可直接回到闲置比例。
- 修正资产管线的“最长姿态整组缩小”问题：运行纹理统一改为 `200×120` 透明画布，闲置与慢走只补透明边距，不改动任何猫体像素；短跑和跳跃使用固定身份尺度，不再按最长伸展帧自适应缩放。
- App 的透明面板宽度同步从 `80 pt` 调整为 `100 pt`，可见豆花仍保持原来的约二分之一素材尺寸，新增宽度仅用于容纳伸展的四肢和尾巴。
- v0.8.1 的身份锁、生成提示词、透明源图、运行时联络表和动画预览位于 `Docs/Art/PixelDemo/v9-identity-lock/`。

## 跑累休息与点击侧翻（v0.9）

- 根据最新加入的伏卧、香箱、侧躺、四脚朝天照片和 12 秒抬爪视频，新增 `tired-down`、`rest-loop`、`rest-reaction` 三套独立八帧动作。
- 体力由行为连续驱动：短跑明显消耗，走路轻微消耗，静止与伏卧恢复；体力不足时先减速，并等待短跑植足相位后伏地。
- 伏地与起身共用一套可逆关节序列；休息循环约 `6.4 s`，不使用整只猫缩放模拟呼吸。
- 休息稳定阶段点击豆花，会播放“香箱→侧翻露腹→抬前爪→翻回香箱”，不切换成对话站姿。
- 菜单“跑到累为止”可直接验收体力触发；“趴下休息”和启动参数 `--action=rest`、`--action=rest-reaction` 可分别验收伏地与侧翻。
- 设计、提示词、最新真实素材参考板、生成源图和 QA 产物位于 `Docs/Art/PixelDemo/v10-tired-rest/`。

## 真实窗口边缘互动（v0.10）

- 使用 CoreGraphics 可见窗口列表和稳定窗口编号定位最前方正常窗口，只读取所属进程与矩形边界，不采集窗口画面。
- “跳到当前窗口”以连续抛物线移动透明面板，到达后播放八帧可逆落座序列；脚底基线固定在窗口顶边。
- 八帧驻留循环保持骨盆、脚底和胸底不动，只表现慢眨眼、耳朵、视线和尾尖的低频变化，因此跟随窗口时不会像手持镜头一样晃。
- 点击驻留豆花会播放独立八帧拍边缘序列。首轮因体宽比驻留姿态大约 18% 被拒绝，修复版整组按批准坐姿重新生成，转场宽高误差不超过 2 px。
- 目标窗口消失时先反向起身，再沿连续轨迹返回地面；拖动豆花到窗口顶边 24 pt 内也会自动吸附坐下。
- 设计、提示词、生成源图、运行帧、最终联络表、时间线和 GIF 位于 `Docs/Art/PixelDemo/v11-window-interaction/`。

## 验证目标

- 一眼识别豆花的圆脸、金渐层毛色、黄绿眼睛、奶油色胸口和粗尾巴。
- 闲置时只保留 4.6 秒的极轻呼吸，不再切换整张身体素材，避免高频闪图。
- 行走与跑步使用独立八相猫科步态，步频与实际地面速度锁定，桌面位移以 60Hz 更新。
- 八帧共用固定脚底基线，避免类似手持摄像的上下晃动。

## 生成方式

使用 Codex 内置 `imagegen` 生成像素角色图集；输入照片仅作为豆花身份和外形参考。生成原图使用纯色 `#ff00ff` 背景，再在本地扣取透明度、分割帧并对齐脚底。

### v1 提示词

```text
Use case: stylized-concept
Asset type: production sprite sheet for a macOS desktop pet demo
Input images: Image 1 is the identity reference for the real cat Douhua; synthesize the same individual cat, do not copy the room/background.
Primary request: create one clean 4-column by 2-row animation sprite sheet containing exactly eight full-body frames of the same cat, all facing right and staying in place. Top row frames 1-4: relaxed standing idle, gentle inhale with chest raised by one pixel, slow blink with eyes half closed, tiny left-ear twitch plus tail-tip curl. Bottom row frames 5-8: a natural four-phase feline walk cycle: front contact, weight-down, passing, push-off/up. The four walking frames must form a seamless cycle.
Subject identity: extremely round fluffy golden shaded cat; stocky body and short legs; small slightly outward ears; large yellow-green round eyes with Douhua's mildly serious expression; warm golden coat with darker shaded crown/back; cream muzzle, chin, chest, belly and inner legs; thick fluffy tail with a dark brown tip. Keep the cat recognizably Douhua, not a generic orange tabby.
Style/medium: polished high-detail pixel art, logical sprite resolution about 128x96 per frame, enlarged with crisp nearest-neighbor pixels; restrained 24-32 color palette; hand-authored game sprite quality; no anti-aliasing, no painterly blur, no gradients outside deliberate pixel clusters.
Composition/framing: exactly 4 equal columns and 2 equal rows; every cat centered in its cell at identical scale and camera angle; entire ears, paws and tail visible; identical ground baseline across all eight cells; generous padding; no grid lines, borders, labels or separators.
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background filling every cell, with no floor plane, shadows, gradients, texture, lighting variation or gaps. Do not use #ff00ff anywhere in the cat.
Constraints: identity, face shape, coat pattern, body proportions and sprite dimensions must stay identical across all frames; motion changes only what anatomy requires; crisp closed silhouette; no extra limbs; no duplicate body parts; no cast shadow; no text; no watermark.
Avoid: generic orange cat, slim cat, triangular face, oversized anime eyes, chibi proportions, unstable camera, changing fur pattern, changing sprite scale, smeared motion, blended frames, photorealism.
```

### v2 最终提示词

```text
Use case: identity-preserve
Asset type: revised production sprite sheet for the Douhua macOS pixel desktop pet
Input images: Image 1 is the primary identity and anatomical-proportion reference for the real cat Douhua. Image 2 is the previous pixel sprite sheet and is only a style/layout reference; correct its overly fat body, overly orange coat, short-looking legs, and short tail.
Primary request: create a refined v2 sprite sheet in exactly 4 equal columns by 2 equal rows, containing exactly eight full-body frames of the same cat, all facing right and staying in place. Top row frames 1-4: relaxed standing idle, very gentle inhale, slow blink, tiny ear twitch with a subtle tail-tip movement. Bottom row frames 5-8: one anatomically plausible seamless four-phase feline walk cycle: front contact, weight-down, passing, push-off/up.
Identity and corrected anatomy: match the real Douhua in Image 1. Keep the unmistakably round face, fluffy cheeks, small wide-set slightly rounded ears, olive yellow-green eyes and mildly serious expression. The body is fluffy and sturdy but NOT obese: make the torso/abdomen visibly about 15-20 percent narrower and less barrel-shaped than Image 2; show naturally longer lower legs and clear paw separation; reduce the oversized chest and belly while retaining soft fur volume. Use a normal medium stocky adult-cat silhouette, not slim and not chibi. Make the tail long, thick and softly tapered with a distinct darker tip, matching Image 1.
Color and markings: muted natural golden-shaded coat rather than bright orange; cooler taupe-brown/gray-brown tipping on the crown, spine and upper sides; warm cream muzzle, chin, chest, underside and inner legs; subtle darker leg and tail markings; olive green eyes. Maintain the same marking placement across all eight frames.
Style/medium: more refined and deliberate high-detail pixel art than Image 2, logical sprite resolution about 144x108 per frame, crisp nearest-neighbor pixels, controlled pixel clusters, clean silhouette, restrained 28-40 color palette. Reduce noisy dithering and random speckles; prioritize readable facial features, coat shading and anatomy. No anti-aliasing, painterly blur or photographic softness.
Composition/framing: identical camera, scale and anatomy in every cell; whole ears, paws and full tail visible; each cat centered consistently; all paws share one ground baseline; ample padding; no grid lines, borders, labels or separators.
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background filling every cell, with no floor plane, shadow, gradient, texture, reflection, lighting variation or gaps. Do not use #ff00ff in the cat.
Constraints: preserve Douhua's real identity and round head while correcting only the exaggerated obesity and orange saturation of Image 2; keep proportions, face, coat pattern and scale consistent across frames; motion changes only what feline anatomy requires; crisp closed silhouettes; no extra limbs; no duplicate body parts; no text; no watermark.
Avoid: obese barrel body, huge belly, squat stumpy legs, oversized chibi head, generic orange tabby, bright orange coat, slim oriental-cat silhouette, triangular face, tall pointed ears, anime eyes, short tail, inconsistent fur pattern, unstable camera, changing scale, smeared motion, blended frames, photorealism.
```

### v4 最终提示词

```text
Use case: identity-preserve
Asset type: v4 tiny pixel sprite sheet engineered to have zero limb clipping
Input images: Image 1 is the real Douhua identity reference. Image 2 is the latest pixel-sheet style/proportion reference. Keep the same corrected Douhua face, muted gray-gold palette and non-obese body, but simplify the leg silhouette for tiny display.
Primary request: exactly one 4-column by 2-row sprite sheet containing exactly eight strict right-facing orthographic side-view frames. Top row 1-4: planted neutral idle, tiny inhale, slow blink, tiny ear/tail-tip response. Bottom row 5-8: a seamless natural four-phase walk expressed through one clearly visible near-side foreleg and one clearly visible near-side hind leg: contact, weight-down, passing, push-off.
Zero-clipping silhouette rule: draw exactly TWO visible legs in every frame—one front leg attached directly below the shoulder and one hind leg attached directly below the hip. The two far-side legs are completely occluded behind the near-side legs/body and must NOT be drawn at all. There must be no dark far-leg silhouettes, no brown shapes under the belly, no extra paws, no fifth limb, no merged limbs, no leg crossing, no detached pixels and no limb emerging from the center of the abdomen. Keep a clean transparent gap below the belly between the one foreleg and one hind leg. Each visible leg is continuous from body joint to paw and uses the same golden fur texture as the body.
Identity: unmistakably Douhua—round fluffy face, small wide-set rounded ears, olive yellow-green mildly serious eyes, muted golden shaded coat with cool taupe/gray-brown tipping on crown and spine, cream muzzle/chin/chest/underside, sturdy but not obese torso, long thick darker-tipped tail.
Style/medium: highly refined controlled pixel art specifically readable at a 160x120 logical canvas and 1x desktop size; crisp nearest-neighbor pixels, clean clusters and outline, restrained 28-40 colors, minimal dithering. No antialiasing, blur, photographic softness or painterly marks.
Locked registration: identical head, torso, coat markings, camera, scale and ground line across all frames. The torso must not stretch or change width. Only the two visible leg joints, tail tip, ear and eyelids may move.
Composition: exactly four equal columns and two equal rows; each cat centered consistently with full ears, two visible paws and full tail inside the cell; generous padding; no grid, borders, labels or separators.
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background across the full sheet; no shadow, floor, gradient, texture, gaps or lighting variation. Never use #ff00ff in the cat.
Constraints: exactly two visible anatomically attached legs in each frame; no text, watermark or extra animals.
Avoid: any far-side legs, dark brown leg blobs, four separately visible legs, overlapping limbs, crossing legs, detached paws, extra limbs, body deformation, camera shake, obesity, orange saturation, chibi proportions, generic tabby.
```

### v5 四腿修正最终提示词

```text
Use case: identity-preserve
Asset type: corrected v5 production pixel-art sprite sheet for the Douhua macOS desktop pet
Input images: Image 1 is the edit target and exact style/layout/character-registration reference. Image 2 is the real Douhua identity and anatomy reference. Preserve Image 1's same muted gray-gold pixel-art Douhua, face, body proportions, scale, palette, 4-by-2 sheet layout and solid magenta backdrop; change the leg anatomy and gait only.
Primary request: redraw the legs in all eight frames so the cat is anatomically complete and visibly has FOUR legs. Top row frames 1-4 are planted idle variants: show two forelegs and two hind legs, with all four paws readable; near-side foreleg and hind leg are fully visible, while far-side foreleg and hind leg are partially visible behind them and offset horizontally by several pixels. Bottom row frames 5-8 are a seamless natural four-phase feline walk cycle: all four legs participate as two diagonal pairs, with near and far legs alternating through contact, support, passing and push-off.
Leg readability rules: every leg must connect continuously from its correct shoulder or hip to its own paw. Far-side legs use slightly darker, lower-contrast golden-brown fur but remain unmistakably legs, not shadows. Separate adjacent paws with at least a narrow magenta gap or a clear dark outline. In every frame there must be exactly four legs and exactly four paws—no missing leg, no merged pair, no central belly stump, no detached paw, no crossing through another leg, no fifth limb. The far foreleg attaches beneath the far shoulder; the far hind leg attaches beneath the far hip. Preserve a clean belly gap between front and rear leg pairs.
Locked invariants: keep Douhua's face, round head, small wide-set ears, olive yellow-green eyes, mildly serious expression, sturdy non-obese torso, muted gray-gold coat markings, thick dark-tipped tail, pixel resolution, camera, framing, ground baseline and body registration consistent across all eight frames. The head and torso must not wander, stretch or change scale.
Style/medium: refined controlled pixel art, crisp nearest-neighbor pixel clusters, minimal dithering, no antialiasing, no blur, no photographic softness.
Scene/backdrop: perfectly flat solid #ff00ff across the entire sheet; no floor, shadow, gradient, grid, labels, text or watermark. Never use #ff00ff inside the cat.
Avoid: two-legged silhouette, hidden/missing far legs, dark amorphous blobs, overlapping or clipping limbs, crossed legs, fused paws, detached pixels, body morphing, camera shake, obesity, orange saturation, generic tabby.
```

## 运行

```bash
Scripts/build-pixel-demo.sh
open ~/Applications/DouhuaPixelDemo.app
```
