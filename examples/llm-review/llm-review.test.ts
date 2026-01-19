/**
 * LLM-as-Judge Review Library - Test Examples
 *
 * These examples show Ralph how to use llm-review for perceptual quality tests.
 * Ralph discovers these patterns during src/lib exploration.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { createReview, reviewText, reviewImage, reviewStrict } from './llm-review';
import * as fs from 'fs';
import * as path from 'path';

// =============================================================================
// Text Evaluation Examples
// =============================================================================

describe('Text quality evaluation', () => {
  it('evaluates welcome message tone', async () => {
    const message = `
      Hey there! 👋 Welcome to ColorPal.

      We're excited to help you create beautiful color palettes
      from your favorite photos. Just upload an image and we'll
      extract the perfect colors for your next project.

      Ready to get started?
    `;

    const result = await createReview({
      criteria: 'Warm, conversational tone appropriate for design professionals; clear value proposition',
      artifact: message,
    });

    expect(result.pass).toBe(true);
  });

  it('evaluates error message clarity', async () => {
    const errorMessage = `
      Oops! We couldn't process that image.

      This might be because:
      • The file is larger than 5MB
      • The format isn't supported (try PNG, JPG, or WebP)
      • The file might be corrupted

      Want to try a different image?
    `;

    const result = await reviewText(
      errorMessage,
      'Helpful, non-technical error message that guides user to resolution'
    );

    expect(result.pass).toBe(true);
  });

  it('evaluates API documentation completeness', async () => {
    const apiDoc = `
      ## extractColors(image: File): Promise<ColorPalette>

      Extracts dominant colors from an uploaded image.

      ### Parameters
      - image: File object (PNG, JPG, WebP up to 5MB)

      ### Returns
      ColorPalette object containing:
      - colors: Array of Color objects (5-10 colors)
      - dominant: The most prominent color

      ### Example
      \`\`\`typescript
      const palette = await extractColors(file);
      console.log(palette.dominant.hex); // "#4A90D9"
      \`\`\`
    `;

    const result = await reviewStrict(
      apiDoc,
      'Complete API documentation with parameters, return type, and working example'
    );

    expect(result.pass).toBe(true);
  });
});

// =============================================================================
// Vision Evaluation Examples
// =============================================================================

describe('Visual quality evaluation', () => {
  const tmpDir = './tmp';

  beforeAll(() => {
    // Ensure tmp directory exists for screenshots
    if (!fs.existsSync(tmpDir)) {
      fs.mkdirSync(tmpDir, { recursive: true });
    }
  });

  it('evaluates dashboard visual hierarchy', async () => {
    // Assume screenshot was taken by test setup
    const screenshotPath = path.join(tmpDir, 'dashboard.png');

    // Skip if screenshot doesn't exist (CI environment)
    if (!fs.existsSync(screenshotPath)) {
      console.log('Skipping: screenshot not found');
      return;
    }

    const result = await createReview({
      criteria: 'Clear visual hierarchy with obvious primary action; information organized logically',
      artifact: screenshotPath,
    });

    expect(result.pass).toBe(true);
  });

  it('evaluates color palette visual harmony', async () => {
    const screenshotPath = path.join(tmpDir, 'palette-output.png');

    if (!fs.existsSync(screenshotPath)) {
      console.log('Skipping: screenshot not found');
      return;
    }

    const result = await reviewImage(
      screenshotPath,
      'Colors work well together; palette feels cohesive and intentional'
    );

    expect(result.pass).toBe(true);
  });

  it('evaluates brand consistency', async () => {
    const screenshotPath = path.join(tmpDir, 'homepage.png');

    if (!fs.existsSync(screenshotPath)) {
      console.log('Skipping: screenshot not found');
      return;
    }

    const result = await createReview({
      criteria: 'Professional brand identity suitable for creative professionals; consistent visual language',
      artifact: screenshotPath,
      intelligence: 'smart', // Use smart for complex aesthetic judgment
    });

    expect(result.pass).toBe(true);
  });

  it('evaluates mobile responsiveness', async () => {
    const screenshotPath = path.join(tmpDir, 'mobile-view.png');

    if (!fs.existsSync(screenshotPath)) {
      console.log('Skipping: screenshot not found');
      return;
    }

    const result = await reviewImage(
      screenshotPath,
      'Content readable and accessible on mobile; touch targets appropriately sized; no horizontal scroll'
    );

    expect(result.pass).toBe(true);
  });
});

// =============================================================================
// UX Flow Evaluation Examples
// =============================================================================

describe('UX flow evaluation', () => {
  it('evaluates onboarding flow clarity', async () => {
    const onboardingSteps = `
      Step 1: "Upload your first image"
      [Large upload button with drag-drop zone]
      [Skip option in corner]

      Step 2: "Here's your palette!"
      [5 color swatches extracted from image]
      [Copy buttons on each color]

      Step 3: "Export or save"
      [Export as PNG, CSS, JSON buttons]
      [Save to library option]
    `;

    const result = await reviewStrict(
      onboardingSteps,
      'Onboarding flow is intuitive with clear progression; each step has obvious next action; can be skipped'
    );

    expect(result.pass).toBe(true);
  });

  it('evaluates empty state helpfulness', async () => {
    const emptyState = `
      🎨 Your palette library is empty

      Upload an image to extract your first color palette,
      or browse our curated collection for inspiration.

      [Upload Image] [Browse Collection]
    `;

    const result = await reviewText(
      emptyState,
      'Empty state provides clear guidance; offers multiple paths forward; not discouraging'
    );

    expect(result.pass).toBe(true);
  });
});

// =============================================================================
// Content Quality Examples
// =============================================================================

describe('Content quality evaluation', () => {
  it('evaluates marketing copy effectiveness', async () => {
    const landingCopy = `
      # Extract Perfect Palettes in Seconds

      Stop guessing at colors. Upload any image and get a
      professionally curated palette instantly.

      ✓ Works with photos, screenshots, and artwork
      ✓ Export to CSS, Figma, or your favorite tools
      ✓ Free for personal projects

      [Get Started Free]
    `;

    const result = await createReview({
      criteria: 'Clear value proposition; specific benefits not vague claims; compelling call to action',
      artifact: landingCopy,
      intelligence: 'smart',
    });

    expect(result.pass).toBe(true);
  });

  it('evaluates technical writing clarity', async () => {
    const technicalExplanation = `
      ## How Color Extraction Works

      We use k-means clustering in LAB color space to identify
      dominant colors. LAB is perceptually uniform, meaning
      colors that look similar to humans are mathematically
      close together.

      The algorithm:
      1. Converts your image to LAB color space
      2. Clusters pixels into 5-10 groups
      3. Returns the center of each cluster as a palette color

      This approach produces palettes that feel natural and
      match what you'd pick by eye.
    `;

    const result = await reviewText(
      technicalExplanation,
      'Technical concept explained accessibly; no jargon without explanation; practical takeaway'
    );

    expect(result.pass).toBe(true);
  });
});
