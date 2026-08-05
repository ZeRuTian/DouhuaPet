# Douhua Realistic Art Brief v1

## Non-Negotiable Direction

Final Douhua art must look like the real Douhua as closely as possible. The required style is realistic / photorealistic soft studio pet portrait, suitable for later transparent desktop-pet sprites. Reject flat vector, cartoon, chibi, anime, painterly caricature, generic orange tabby, generic British Shorthair, or any image that only loosely resembles the reference board.

The current v0.2 assets are a temporary deterministic vector/raster fallback. They are useful for runtime testing only and must not be mistaken for the requested final realistic art.

## Factual Sources Inspected

- Character bible: `Docs/DouhuaCharacterBible.md`
- v0.2 offline model sheet: `Docs/Art/douhua-model-sheet-v0.2-offline.png`
- v0.2 runtime sprites: `Sources/DouhuaPet/Resources/Assets/Douhua/v0.2/`
- Reference board inspected in place: `../豆花角色参考板_20260710.jpg`

Do not modify, copy, upload, bundle, or commit original personal photos or videos. Use them only as owner-provided visual references during generation and review.

## Identity Lock

Douhua is a golden shaded British Shorthair with these locked traits:

- Round, broad British Shorthair face; compact, plush head shape, not a long wedge-shaped face.
- Very large green eyes with dark eyeliner rims; eyes are the strongest identity anchor.
- Small upright ears, set wide on the rounded head; no oversized kitten ears.
- Pink nose, pale muzzle, pale chin, and pale chest / belly.
- Overall warm golden coat with darker shading on the top of the head, back, sides, tail, and tail tip.
- Dense short plush fur with subtle shaded ticking; not long-haired, not sleek, not striped orange-tabby fur.
- Compact, full, rounded body; short sturdy legs and paws.
- Thick rounded tail with a darker tip.
- Rest-dominant body language: loaf, side-lying, belly-up, sleeping, slow observing; calm rather than energetic.

Anti-drift rules:

- Do not turn Douhua into a generic orange tabby: no strong tiger stripes, no lanky body, no narrow face.
- Do not turn Douhua into a generic blue/gray British Shorthair or silver shaded cat.
- Do not make the face cute-anime, chibi, toy-like, plush-toy, mascot, sticker, or flat vector.
- Do not remove the green eyes, dark eye rims, pink nose, pale muzzle/chin/chest, rounded body, thick tail, or dark tail tip.
- Do not over-clean the coat into a single beige color; keep warm golden shaded fur with darker back/head/tail.
- Do not exaggerate markings beyond the reference board. Douhua is shaded and plush, not sharply striped.
- Do not change age, breed impression, body proportions, eye color, or tail thickness between poses.

## Flux / FAL-Ready Image-to-Image Model-Sheet Prompt

Use multiple owner-provided reference images from the reference board as image-to-image identity references. Prefer models/routes that support multi-image reference conditioning, IP-Adapter-like identity preservation, or equivalent reference strength. Keep all personal reference media outside the repository.

Prompt:

```text
Create a realistic photorealistic soft studio pet portrait model sheet of the same real cat named Douhua, using the provided reference images as strict identity references. Douhua is a golden shaded British Shorthair cat: broad round plush face, very large green eyes with dark eyeliner rims, small wide-set upright ears, pink nose, pale cream muzzle, pale chin, pale chest and belly, compact rounded body, short sturdy legs, thick rounded tail with a darker tail tip, dense short plush warm golden fur with darker shaded head, back, sides and tail. Preserve the exact individual identity, face shape, eye color, eye-rim darkness, muzzle color, body fullness, tail thickness, and coat distribution from the references.

Orthographic production model sheet on a clean neutral light gray background, soft even studio lighting, no dramatic shadows, no furniture, no props, no floor clutter. Arrange the same cat in separate clearly spaced views: front standing view, left three-quarter view, right three-quarter view, pure side profile, loaf pose, curled sleeping pose, and isolated tail/detail callout showing the thick tail and darker tail tip. Consistent scale and proportions across all views. Real camera lens look, detailed short plush fur, natural whiskers, realistic paws, realistic anatomy, calm expression, high resolution, sharp but soft pet portrait lighting, production-ready reference sheet for transparent PNG sprite extraction.
```

Suggested controls:

- Use low-to-medium denoise for identity preservation when starting from reference images; increase only if composition fails.
- Use fixed seed batches for comparison; keep the best identity match, not the prettiest generic cat.
- If the backend supports reference weights, prioritize identity / face / eyes over pose variety.
- Generate at high resolution, then crop each pose manually or with segmentation only after approval.

## Negative Prompt

```text
cartoon, chibi, anime, manga, mascot, sticker, flat vector, logo, icon, toy, plush toy, painterly, watercolor, oil painting, caricature, fantasy creature, generic orange tabby, strong tiger stripes, silver shaded cat, gray cat, blue british shorthair, long hair, maine coon, siamese, persian, narrow face, long muzzle, tiny eyes, yellow eyes, blue eyes, missing dark eyeliner, black nose, red nose, oversized ears, thin tail, missing dark tail tip, skinny body, exaggerated paws, human clothing, collar, bow, props, furniture, text, labels, watermark, signature, multiple different cats, inconsistent markings, cropped ears, cropped tail, cut off paws, harsh shadows, dramatic colored lighting, low resolution, blurry, deformed anatomy, extra limbs
```

## Required Model-Sheet Composition

- One neutral sheet, no decorative framing.
- Views required: front, left 3/4, right 3/4, side profile, loaf, sleeping, tail/detail callout.
- Lighting: soft neutral studio lighting, even exposure, visible fur detail, no hard rim light.
- Background: neutral light gray or white, easy to segment; no household context.
- Camera: eye-level or slightly above, realistic lens perspective without distortion.
- Spacing: each pose separated enough for manual cutout; no overlap between tails, ears, or paws.
- Consistency: same cat, same coat map, same eye color, same face proportions, same tail thickness in every view.
- Transparent-production considerations: preserve full silhouette including ears, whiskers, paws, belly, and tail; leave margin around every pose; avoid white fur blending into pure white background by using light gray when needed; final sprite extraction must produce clean alpha edges and no halos.

## Four-State Sprite Production Prompt

Use the approved realistic model sheet as the identity source. Do not generate sprites from the temporary v0.2 vector fallback.

Prompt:

```text
Create four separate realistic transparent-background desktop-pet sprites of the same real cat Douhua, strictly matching the approved realistic model sheet and reference images. Style: photorealistic soft studio pet portrait, natural short plush golden shaded British Shorthair fur, large green eyes with dark eyeliner rims, pink nose, pale muzzle/chin/chest, compact rounded body, short sturdy paws, thick tail with darker tail tip.

Produce these four states with identical identity, scale, lighting, fur color, face shape, and tail design:
1. walk / slow patrol: calm standing or gentle stepping pose, full body visible, thick tail visible.
2. observe: seated or standing attentive pose, large green eyes open, head slightly lifted, calm expression.
3. loaf: compact loaf pose, paws tucked, round face visible, thick body volume preserved.
4. sleep: curled or side-sleeping pose, peaceful, face still identifiable, tail visible with darker tip.

Each sprite must be isolated on transparent background or clean cutout-ready neutral background, full body uncropped, no props, no shadows baked outside the silhouette, no labels, no accessories, production-ready for 360x440 RGBA PNG extraction.
```

Consistency constraints:

- All four sprites must read as the same individual Douhua before any filename or context is shown.
- Match the approved model sheet first, then match pose requirements.
- Keep canvas planning compatible with the existing runtime contract: four same-name states, transparent PNG, full silhouette, no cropped ears/tail/paws, no external personal media bundled.
- Final integration only happens after the realistic model sheet passes identity and style approval.

## Objective Approval Checklist

Reject the output if any item fails:

- Looks like the real Douhua from `../豆花角色参考板_20260710.jpg`, not merely a plausible British Shorthair.
- Genuinely realistic / photorealistic soft studio pet portrait style.
- Not flat vector, cartoon, chibi, anime, painterly, mascot, sticker, or plush-toy style.
- Not a generic orange tabby; no strong tabby striping or lanky orange-cat anatomy.
- Large green eyes and dark eyeliner rims are present and consistent.
- Pink nose, pale muzzle, pale chin, and pale chest / belly are visible where pose allows.
- Warm golden shaded coat with darker head/back/tail and darker tail tip is preserved.
- Round broad face, compact rounded body, short sturdy legs, and thick tail match the character bible.
- Required model-sheet poses are present: front, left/right 3/4, side, loaf, sleeping, tail/detail.
- Same identity across all views; no pose looks like a different cat.
- Neutral lighting/background and enough spacing for transparent extraction.
- No props, text, watermark, clothing, collars, or household background.
- Full silhouettes are uncropped; ears, whiskers, paws, belly, and tail are usable for sprite production.

## Implemented Generation Route (2026-07-11)

The realistic v1 model sheet and five runtime poses were generated with the Codex built-in imagegen route using the owner-provided references. Cutout sources used a flat `#ff00ff` background, followed by the bundled local chroma-removal helper and deterministic Swift/AppKit normalization. Final prompts are recorded in `Docs/Art/DouhuaImageGenPrompts-v1.md`.

Original owner photos and videos are not copied into the repository or app bundle. The installed app remains fully offline at runtime.

## Earlier Local-Backend Audit

Read-only audit result on this Mac:

- No usable `comfyui`, `comfy`, `mflux`, or `mflux-generate` command was found on `PATH`.
- No ComfyUI, Draw Things, DiffusionBee, or Mochi Diffusion app was found in `/Applications` or `~/Applications`.
- No running local ComfyUI service responded at `http://127.0.0.1:8188/system_stats`.
- No running local Automatic1111-style service responded at `http://127.0.0.1:7860/`.
- A Hermes skill directory exists at `/Users/zerutian/.hermes/skills/creative/comfyui`, but that is workflow/tooling documentation, not an installed active image-generation backend.
- No installed local FLUX checkpoint or usable local model backend was confirmed by the scoped audit.

Recommended route:

1. Use an external hosted Flux/FAL image-to-image route that supports multiple reference images for identity preservation, because no local usable backend was verified.
2. Blocker: external FAL/Flux requires available service credentials / account access outside this repository. Do not read or print credentials from this Mac; provide them only through the user's normal secure runtime when actually generating.
3. Local blocker: if generation must be fully offline, install/configure a local backend and model separately before this project can generate the requested realistic art. This task did not install software, download models, configure accounts, or alter settings.
4. Keep the approved realistic model sheet as the required gate. Do not replace runtime assets until the model sheet passes the approval checklist above.
