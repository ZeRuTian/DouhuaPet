# Douhua realistic asset prompt set v1

## Execution route

- Generator: Codex built-in `imagegen` mode.
- Identity references: the owner-provided Douhua photographs and reference board.
- Cutout source background: uniform `#ff00ff` chroma key, with no floor, shadow, gradient, reflection, halo, text, or props.
- Local finishing: the imagegen chroma-removal helper, then `Scripts/PrepareRealisticAssets.swift` for deterministic alpha bounding, common scale, baseline alignment, and 480×440 output.
- Original owner photographs are reference-only and are not copied into the app bundle.

## Shared identity-lock prompt

```text
Create the exact same real cat Douhua shown in the references. Identity fidelity is more important than prettiness. Douhua is a compact, full-bodied golden shaded British Shorthair with a very broad round plush face, short round muzzle, very large sage-green eyes with strong dark eyeliner rims, small wide-set upright ears, dusty-pink nose, pale cream muzzle/chin/chest, warm golden coat with substantially darker shaded crown/back/sides, subtle dark-tipped ticking rather than orange tiger stripes, short sturdy paws, and a thick rounded tail with a distinctly darker tip.

Style: genuinely photorealistic soft-studio pet photography, real dense short plush fur, natural whiskers and correct feline anatomy. Exactly one cat. Preserve the same face, eye shape and color, coat map, body fullness, paw proportions, tail thickness and dark tail tip in every pose.

Avoid: cartoon, chibi, anime, mascot, sticker, illustration, painterly, plush toy, generic orange tabby, strong stripes, gray or silver cat, long hair, narrow face, tiny/yellow/blue eyes, oversized ears, thin tail, missing dark tail tip, different cats, extra limbs, cropped anatomy, collar, accessory, text, watermark or signature.
```

## Model sheet

```text
On a seamless neutral light-gray studio background, arrange the same Douhua in seven clearly separated, full-body views: front standing, left three-quarter seated, right three-quarter seated, pure side-profile standing, compact loaf facing camera, curled side-sleeping, and a tail/coat detail callout. Use soft even neutral lighting, consistent scale and identity, ample whitespace, no overlap, no labels, no props, and no cropped ears, whiskers, paws or tail.
```

## Runtime poses

Each pose appended the following cutout contract:

```text
Use a perfectly flat solid #ff00ff chroma-key background. The background must be one uniform color with no shadows, gradients, texture, floor plane, reflections, halos, or lighting variation. Do not use #ff00ff in the subject. Keep the full silhouette separated from the background with generous padding. No cast or contact shadow.
```

### Observe

```text
Calm three-quarter seated pose facing slightly left while looking toward the viewer. Both short front paws close together. Thick tail curled along the ground with dark tip visible. Full body centered on a portrait-friendly canvas; alert but quiet expression.
```

### Slow walk

```text
Side profile walking toward screen left, head turned slightly toward the viewer so the round cheek and green eye remain recognizable. Compact low body, short legs in a believable gentle mid-step, one front paw lifting, thick tail held low behind with dark tip fully visible. Calm heavy walk, not running or jumping.
```

### Loaf

```text
True compact loaf facing slightly left and looking calmly at the viewer: shoulders rounded, both front paws fully tucked, belly low, body short and full. Thick tail wraps along one side with dark tip visible. Do not show stretched front legs or a cushion-shaped body.
```

### Sleep

```text
Peaceful low side-sleep: head resting gently on the front paws, eyes naturally closed, ears relaxed, round cheek and pink nose visible, body loosely curled rather than stretched thin, thick tail curved along the body with dark tip visible. Do not make a sitting cat with closed eyes.
```

### Petted response

```text
Compact low loaf/crouch immediately after a gentle head pet, with no human hand shown. Head dips slightly, green eyes become naturally half-closed, and ears relax slightly outward without flattening in fear. Soft content expression, paws close, thick dark-tipped tail beside the body.
```
