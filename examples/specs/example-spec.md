# Spec: Color Palette Extraction

> This is an example specification showing the recommended format for Ralph v2 specs.

## Overview

Extract dominant colors from uploaded images to generate color palettes for design workflows.

## User Story (JTBD)

**When I** upload a photo or screenshot
**I want to** automatically extract the dominant colors
**So that** I can create a coordinated color palette for my design project

## Acceptance Criteria

### Functional Requirements

- [ ] Accepts image uploads (PNG, JPG, WebP) up to 5MB
- [ ] Extracts 5-10 dominant colors from each image
- [ ] Returns colors in HEX, RGB, and HSL formats
- [ ] Processes images in under 100ms (p95)
- [ ] Handles grayscale images (returns shades)
- [ ] Handles images with transparency (ignores alpha)

### Quality Requirements

- [ ] Color extraction produces visually representative results
- [ ] Palette ordering feels natural (most prominent first)
- [ ] UI feedback is immediate (<200ms to first response)

### Edge Cases

- [ ] Gracefully handles corrupt/invalid images
- [ ] Handles single-color images (returns that color)
- [ ] Handles very small images (<10px)

## Test Requirements

### Programmatic Tests

```typescript
// Unit tests
describe('ColorExtractor', () => {
  it('extracts 5-10 colors from valid image', async () => {
    const result = await extractColors(testImage);
    expect(result.colors.length).toBeGreaterThanOrEqual(5);
    expect(result.colors.length).toBeLessThanOrEqual(10);
  });

  it('completes within 100ms', async () => {
    const start = performance.now();
    await extractColors(largeTestImage);
    expect(performance.now() - start).toBeLessThan(100);
  });

  it('handles grayscale images', async () => {
    const result = await extractColors(grayscaleImage);
    expect(result.colors.every(c => c.saturation === 0)).toBe(true);
  });
});
```

### Perceptual Tests (LLM-as-Judge)

```typescript
// Using llm-review library
describe('Color extraction quality', () => {
  it('produces visually representative palette', async () => {
    const result = await createReview({
      criteria: 'Palette colors accurately represent the dominant colors visible in the source image',
      artifact: './tmp/palette-comparison.png',
      intelligence: 'smart',
    });
    expect(result.pass).toBe(true);
  });
});
```

### Visual Tests (UI Verification)

```typescript
// Using visual-testing library
describe('Color palette UI', () => {
  let session: VisualTestContext;

  beforeAll(async () => {
    session = await createVisualTestSession({ baseUrl: 'http://localhost:3000' });
  });

  afterAll(async () => {
    await session.close();
  });

  it('displays palette with clear visual hierarchy', async () => {
    await session.navigate('/palette');
    const result = await session.assertLayout(
      'Color swatches prominently displayed; hex codes readable; copy buttons discoverable'
    );
    expect(result.pass).toBe(true);
  });

  it('is responsive across viewports', async () => {
    await session.navigate('/palette');
    const results = await session.assertResponsive(
      'Swatches stack on mobile; codes remain readable; touch targets adequate'
    );
    results.forEach(r => expect(r.pass).toBe(true));
  });

  it('meets accessibility requirements', async () => {
    await session.navigate('/palette');
    const result = await session.assertAccessibility(
      'Color values have sufficient contrast; swatches have accessible names'
    );
    expect(result.pass).toBe(true);
  });
});
```

## Technical Notes

### Suggested Approach

- K-means clustering in LAB color space
- Convert to sRGB for output
- Use median cut as fallback for edge cases

### Dependencies

Consider existing libraries:
- `quantize` - Fast color quantization
- `vibrant.js` - Palette extraction
- `color-thief` - Dominant color extraction

### Location

`src/lib/color-extraction.ts` - Core extraction logic
`src/components/ColorPalette.tsx` - UI component

## Out of Scope

- Color naming (e.g., "Ocean Blue")
- Color harmony suggestions
- Palette saving/persistence
- Multiple image comparison

## Related Specs

- `specs/image-upload.md` - Upload handling
- `specs/palette-export.md` - Export functionality
