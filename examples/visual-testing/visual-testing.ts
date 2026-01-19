/**
 * Visual Testing Library for Ralph v2
 *
 * Adds visual verification as a backpressure tier for UI acceptance criteria:
 * layout, responsiveness, component appearance, interactive states, accessibility.
 *
 * Uses agent-browser for browser control and LLM-as-Judge for visual assertions.
 *
 * Usage:
 *   import { createVisualTestSession, assertPageVisual } from './visual-testing';
 *
 *   // Full session management
 *   const session = await createVisualTestSession({ baseUrl: 'http://localhost:3000' });
 *   await session.navigate('/dashboard');
 *   await session.assertLayout('Clear visual hierarchy with sidebar navigation');
 *   await session.close();
 *
 *   // Quick one-off checks
 *   const result = await assertPageVisual('http://localhost:3000', 'Professional design');
 */

import Anthropic from '@anthropic-ai/sdk';
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

// =============================================================================
// Types
// =============================================================================

export interface VisualTestConfig {
  /** Base URL for the application under test */
  baseUrl: string;

  /** Directory for screenshots and baselines (default: ./tmp/visual-testing) */
  outputDir?: string;

  /** Intelligence level for visual assertions (default: 'smart') */
  intelligence?: 'fast' | 'smart';

  /** Timeout for browser operations in ms (default: 30000) */
  timeout?: number;
}

export interface VisualAssertionResult {
  /** Whether the assertion passed */
  pass: boolean;

  /** Feedback explaining why it failed (only present when pass=false) */
  feedback?: string;

  /** Path to the screenshot taken for this assertion */
  screenshotPath?: string;
}

export interface Viewport {
  width: number;
  height: number;
  name: string;
}

export interface InteractiveStateConfig {
  /** CSS selector for the target element */
  target: string;

  /** State to verify: hover, focus, active, disabled */
  state: 'hover' | 'focus' | 'active' | 'disabled';

  /** Criteria for the visual assertion */
  criteria: string;
}

export interface KeyboardNavigationStep {
  /** Key to press (e.g., 'Tab', 'Enter', 'Escape') */
  key: string;

  /** Expected focused element selector after key press */
  expectedFocus?: string;
}

// =============================================================================
// Viewport Presets
// =============================================================================

export const VIEWPORTS: Record<string, Viewport> = {
  desktop: { width: 1920, height: 1080, name: 'desktop' },
  laptop: { width: 1366, height: 768, name: 'laptop' },
  tablet: { width: 768, height: 1024, name: 'tablet' },
  tabletLandscape: { width: 1024, height: 768, name: 'tablet-landscape' },
  mobile: { width: 375, height: 812, name: 'mobile' },
  mobileLarge: { width: 414, height: 896, name: 'mobile-large' },
};

// =============================================================================
// Internal Utilities
// =============================================================================

const client = new Anthropic();

function getModel(intelligence: 'fast' | 'smart'): string {
  return intelligence === 'smart'
    ? 'claude-sonnet-4-20250514' // Better for nuanced visual judgment
    : 'claude-haiku-4-20250514'; // Fast for simple checks
}

function ensureDir(dir: string): void {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function generateScreenshotName(prefix: string): string {
  const timestamp = Date.now();
  return `${prefix}-${timestamp}.png`;
}

/**
 * Execute agent-browser command
 */
function execAgentBrowser(command: string, timeout: number): string {
  try {
    return execSync(`agent-browser ${command}`, {
      timeout,
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch (error) {
    const err = error as { stderr?: string; message?: string };
    throw new Error(`agent-browser command failed: ${err.stderr || err.message}`);
  }
}

/**
 * Read image file and convert to base64
 */
function readImageAsBase64(imagePath: string): { data: string; mediaType: string } {
  const buffer = fs.readFileSync(imagePath);
  const data = buffer.toString('base64');
  return { data, mediaType: 'image/png' };
}

/**
 * Perform visual assertion using LLM vision
 */
async function performVisualAssertion(
  screenshotPath: string,
  criteria: string,
  intelligence: 'fast' | 'smart'
): Promise<VisualAssertionResult> {
  if (!fs.existsSync(screenshotPath)) {
    return {
      pass: false,
      feedback: `Screenshot not found: ${screenshotPath}`,
      screenshotPath,
    };
  }

  const { data, mediaType } = readImageAsBase64(screenshotPath);

  const systemPrompt = `You are a visual QA expert evaluating UI screenshots against specific criteria.

Your task:
1. Carefully analyze the screenshot
2. Evaluate against the provided criteria
3. Return a JSON response with exactly this format:
   {"pass": true} or {"pass": false, "feedback": "specific reason for failure"}

Rules:
- Be strict but fair in evaluation
- Only pass if criteria are clearly met
- Feedback should be actionable and specific
- Consider accessibility, usability, and visual design
- Return ONLY the JSON, no other text`;

  const userPrompt = `Visual Criteria: ${criteria}

Evaluate this screenshot and return JSON:`;

  const response = await client.messages.create({
    model: getModel(intelligence),
    max_tokens: 512,
    system: systemPrompt,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'text', text: userPrompt },
          {
            type: 'image',
            source: {
              type: 'base64',
              media_type: mediaType as 'image/png',
              data,
            },
          },
        ],
      },
    ],
  });

  const text = response.content
    .filter((block): block is Anthropic.TextBlock => block.type === 'text')
    .map((block) => block.text)
    .join('');

  try {
    const result = JSON.parse(text.trim());
    return {
      pass: Boolean(result.pass),
      feedback: result.pass ? undefined : result.feedback,
      screenshotPath,
    };
  } catch {
    return {
      pass: false,
      feedback: `Failed to parse visual assertion response: ${text}`,
      screenshotPath,
    };
  }
}

/**
 * Compare two screenshots and create a diff composite (requires ImageMagick)
 */
function createDiffComposite(
  baselinePath: string,
  currentPath: string,
  outputPath: string
): boolean {
  try {
    // Create side-by-side comparison with diff highlight
    execSync(
      `compare -metric AE -highlight-color red "${baselinePath}" "${currentPath}" "${outputPath}" 2>/dev/null || true`,
      { encoding: 'utf-8' }
    );
    return true;
  } catch {
    // ImageMagick not available, skip diff composite
    return false;
  }
}

// =============================================================================
// Visual Test Context (Session Management)
// =============================================================================

export class VisualTestContext {
  private config: Required<VisualTestConfig>;
  private currentUrl: string = '';
  private sessionActive: boolean = false;

  constructor(config: VisualTestConfig) {
    this.config = {
      baseUrl: config.baseUrl,
      outputDir: config.outputDir || './tmp/visual-testing',
      intelligence: config.intelligence || 'smart',
      timeout: config.timeout || 30000,
    };
    ensureDir(this.config.outputDir);
  }

  /**
   * Open browser and navigate to initial URL
   */
  async open(initialPath: string = '/'): Promise<void> {
    const url = `${this.config.baseUrl}${initialPath}`;
    execAgentBrowser(`open "${url}"`, this.config.timeout);
    this.currentUrl = url;
    this.sessionActive = true;
  }

  /**
   * Navigate to a path
   */
  async navigate(urlPath: string): Promise<void> {
    const url = `${this.config.baseUrl}${urlPath}`;
    execAgentBrowser(`navigate "${url}"`, this.config.timeout);
    this.currentUrl = url;
  }

  /**
   * Take a screenshot and return path
   */
  async screenshot(name?: string): Promise<string> {
    const filename = name || generateScreenshotName('screenshot');
    const filepath = path.join(this.config.outputDir, filename);
    execAgentBrowser(`screenshot "${filepath}"`, this.config.timeout);
    return filepath;
  }

  /**
   * Set viewport size
   */
  async setViewport(viewport: Viewport): Promise<void> {
    execAgentBrowser(`resize ${viewport.width} ${viewport.height}`, this.config.timeout);
  }

  /**
   * Click an element
   */
  async click(selector: string): Promise<void> {
    execAgentBrowser(`click "${selector}"`, this.config.timeout);
  }

  /**
   * Type text into an element
   */
  async type(selector: string, text: string): Promise<void> {
    execAgentBrowser(`type "${selector}" "${text}"`, this.config.timeout);
  }

  /**
   * Press a key
   */
  async pressKey(key: string): Promise<void> {
    execAgentBrowser(`key "${key}"`, this.config.timeout);
  }

  /**
   * Hover over an element
   */
  async hover(selector: string): Promise<void> {
    execAgentBrowser(`hover "${selector}"`, this.config.timeout);
  }

  /**
   * Focus an element
   */
  async focus(selector: string): Promise<void> {
    execAgentBrowser(`focus "${selector}"`, this.config.timeout);
  }

  /**
   * Wait for a selector to appear
   */
  async waitFor(selector: string, timeout?: number): Promise<void> {
    execAgentBrowser(`wait "${selector}"`, timeout || this.config.timeout);
  }

  /**
   * Get accessibility tree (a11y)
   */
  async getAccessibilityTree(): Promise<string> {
    return execAgentBrowser('accessibility', this.config.timeout);
  }

  /**
   * Close the browser session
   */
  async close(): Promise<void> {
    if (this.sessionActive) {
      execAgentBrowser('close', this.config.timeout);
      this.sessionActive = false;
    }
  }

  // ===========================================================================
  // Visual Assertions
  // ===========================================================================

  /**
   * General visual assertion via LLM
   */
  async assertVisual(name: string, criteria: string): Promise<VisualAssertionResult> {
    const screenshotPath = await this.screenshot(`${name}.png`);
    return performVisualAssertion(screenshotPath, criteria, this.config.intelligence);
  }

  /**
   * Assert layout and visual hierarchy
   */
  async assertLayout(criteria: string): Promise<VisualAssertionResult> {
    const fullCriteria = `Layout/Hierarchy: ${criteria}. Evaluate visual hierarchy, content organization, and structural clarity.`;
    return this.assertVisual('layout', fullCriteria);
  }

  /**
   * Assert spacing consistency
   */
  async assertSpacing(criteria: string): Promise<VisualAssertionResult> {
    const fullCriteria = `Spacing: ${criteria}. Evaluate padding, margins, and whitespace consistency throughout the page.`;
    return this.assertVisual('spacing', fullCriteria);
  }

  /**
   * Assert alignment and grid
   */
  async assertAlignment(criteria: string): Promise<VisualAssertionResult> {
    const fullCriteria = `Alignment: ${criteria}. Evaluate element alignment, grid consistency, and visual balance.`;
    return this.assertVisual('alignment', fullCriteria);
  }

  /**
   * Assert typography
   */
  async assertTypography(criteria: string): Promise<VisualAssertionResult> {
    const fullCriteria = `Typography: ${criteria}. Evaluate font hierarchy, readability, line spacing, and text contrast.`;
    return this.assertVisual('typography', fullCriteria);
  }

  /**
   * Assert color usage
   */
  async assertColors(criteria: string): Promise<VisualAssertionResult> {
    const fullCriteria = `Colors: ${criteria}. Evaluate color harmony, contrast ratios, and brand consistency.`;
    return this.assertVisual('colors', fullCriteria);
  }

  /**
   * Assert responsive design across multiple viewports
   */
  async assertResponsive(
    criteria: string,
    viewports: Viewport[] = [VIEWPORTS.desktop, VIEWPORTS.tablet, VIEWPORTS.mobile]
  ): Promise<VisualAssertionResult[]> {
    const results: VisualAssertionResult[] = [];

    for (const viewport of viewports) {
      await this.setViewport(viewport);
      // Wait for any responsive animations/transitions
      await new Promise((resolve) => setTimeout(resolve, 500));

      const screenshotPath = await this.screenshot(`responsive-${viewport.name}.png`);
      const fullCriteria = `Responsive (${viewport.name} - ${viewport.width}x${viewport.height}): ${criteria}. Content should be readable, touch targets appropriate, no horizontal overflow.`;

      const result = await performVisualAssertion(
        screenshotPath,
        fullCriteria,
        this.config.intelligence
      );
      results.push(result);
    }

    return results;
  }

  /**
   * Assert mobile-specific criteria
   */
  async assertMobile(criteria: string): Promise<VisualAssertionResult> {
    await this.setViewport(VIEWPORTS.mobile);
    await new Promise((resolve) => setTimeout(resolve, 500));

    const fullCriteria = `Mobile: ${criteria}. Evaluate touch target sizes (min 44x44px), thumb-friendly layout, readable text without zooming.`;
    return this.assertVisual('mobile', fullCriteria);
  }

  /**
   * Assert accessibility using both visual and a11y tree
   */
  async assertAccessibility(criteria: string): Promise<VisualAssertionResult> {
    const screenshotPath = await this.screenshot('accessibility.png');
    let a11yTree = '';

    try {
      a11yTree = await this.getAccessibilityTree();
    } catch {
      // a11y tree not available, continue with visual-only check
    }

    const fullCriteria = `Accessibility: ${criteria}. Evaluate color contrast (WCAG AA minimum), focus indicators, alt text presence, semantic structure.${a11yTree ? `\n\nAccessibility Tree:\n${a11yTree}` : ''}`;

    return performVisualAssertion(screenshotPath, fullCriteria, this.config.intelligence);
  }

  /**
   * Assert keyboard navigation sequence
   */
  async assertKeyboardNavigation(
    sequence: KeyboardNavigationStep[],
    criteria: string
  ): Promise<VisualAssertionResult> {
    const screenshots: string[] = [];

    for (let i = 0; i < sequence.length; i++) {
      const step = sequence[i];
      await this.pressKey(step.key);
      await new Promise((resolve) => setTimeout(resolve, 200));

      const screenshotPath = await this.screenshot(`keyboard-nav-${i}.png`);
      screenshots.push(screenshotPath);
    }

    // Evaluate final screenshot with criteria
    const fullCriteria = `Keyboard Navigation: ${criteria}. Focus should be clearly visible at each step, logical tab order, all interactive elements reachable.`;
    return performVisualAssertion(
      screenshots[screenshots.length - 1],
      fullCriteria,
      this.config.intelligence
    );
  }

  /**
   * Assert interactive state (hover, focus, active, disabled)
   */
  async assertInteractiveState(config: InteractiveStateConfig): Promise<VisualAssertionResult> {
    const { target, state, criteria } = config;

    switch (state) {
      case 'hover':
        await this.hover(target);
        break;
      case 'focus':
        await this.focus(target);
        break;
      case 'active':
        await this.click(target);
        break;
      case 'disabled':
        // No action needed, just screenshot
        break;
    }

    await new Promise((resolve) => setTimeout(resolve, 200));

    const fullCriteria = `Interactive State (${state}): ${criteria}. The ${state} state should be clearly distinguishable and provide appropriate visual feedback.`;
    return this.assertVisual(`interactive-${state}`, fullCriteria);
  }

  /**
   * Assert against a baseline image for regression testing
   */
  async assertBaseline(name: string, criteria: string): Promise<VisualAssertionResult> {
    const baselineDir = path.join(this.config.outputDir, 'baselines');
    const baselinePath = path.join(baselineDir, `${name}.png`);
    const currentPath = await this.screenshot(`${name}-current.png`);

    // If no baseline exists, save current as baseline
    if (!fs.existsSync(baselinePath)) {
      ensureDir(baselineDir);
      fs.copyFileSync(currentPath, baselinePath);
      return {
        pass: true,
        feedback: 'Baseline created (first run)',
        screenshotPath: currentPath,
      };
    }

    // Create diff composite if ImageMagick is available
    const diffPath = path.join(this.config.outputDir, `${name}-diff.png`);
    createDiffComposite(baselinePath, currentPath, diffPath);

    // Use LLM to compare baseline vs current
    const baselineData = readImageAsBase64(baselinePath);
    const currentData = readImageAsBase64(currentPath);

    const systemPrompt = `You are a visual regression testing expert comparing two screenshots.

Your task:
1. Compare the baseline (first image) with the current (second image)
2. Identify any visual differences
3. Evaluate if differences are acceptable based on the criteria
4. Return a JSON response with exactly this format:
   {"pass": true} or {"pass": false, "feedback": "specific differences found"}

Rules:
- Minor rendering differences (anti-aliasing, font smoothing) should pass
- Layout shifts, missing elements, or significant color changes should fail
- Return ONLY the JSON, no other text`;

    const userPrompt = `Criteria for acceptable changes: ${criteria}

Compare baseline (first) with current (second) and return JSON:`;

    const response = await client.messages.create({
      model: getModel(this.config.intelligence),
      max_tokens: 512,
      system: systemPrompt,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: userPrompt },
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: 'image/png',
                data: baselineData.data,
              },
            },
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: 'image/png',
                data: currentData.data,
              },
            },
          ],
        },
      ],
    });

    const text = response.content
      .filter((block): block is Anthropic.TextBlock => block.type === 'text')
      .map((block) => block.text)
      .join('');

    try {
      const result = JSON.parse(text.trim());
      return {
        pass: Boolean(result.pass),
        feedback: result.pass ? undefined : result.feedback,
        screenshotPath: currentPath,
      };
    } catch {
      return {
        pass: false,
        feedback: `Failed to parse baseline comparison response: ${text}`,
        screenshotPath: currentPath,
      };
    }
  }

  /**
   * Assert transition/animation smoothness
   */
  async assertTransition(
    trigger: () => Promise<void>,
    criteria: string
  ): Promise<VisualAssertionResult> {
    // Take before screenshot
    await this.screenshot('transition-before.png');

    // Trigger the transition
    await trigger();

    // Take multiple screenshots during transition
    const screenshots: string[] = [];
    for (let i = 0; i < 5; i++) {
      await new Promise((resolve) => setTimeout(resolve, 100));
      const path = await this.screenshot(`transition-frame-${i}.png`);
      screenshots.push(path);
    }

    // Evaluate final frame
    const fullCriteria = `Transition: ${criteria}. Animation should be smooth, no jank or layout jumps, appropriate duration.`;
    return performVisualAssertion(
      screenshots[screenshots.length - 1],
      fullCriteria,
      this.config.intelligence
    );
  }
}

// =============================================================================
// Factory Function
// =============================================================================

/**
 * Create a new visual test session
 */
export async function createVisualTestSession(
  config: VisualTestConfig
): Promise<VisualTestContext> {
  const context = new VisualTestContext(config);
  await context.open();
  return context;
}

// =============================================================================
// Convenience Functions (One-off checks without session management)
// =============================================================================

/**
 * Quick one-off visual check of a page
 */
export async function assertPageVisual(
  url: string,
  criteria: string,
  intelligence: 'fast' | 'smart' = 'smart'
): Promise<VisualAssertionResult> {
  const outputDir = './tmp/visual-testing';
  ensureDir(outputDir);

  const screenshotPath = path.join(outputDir, generateScreenshotName('page'));

  try {
    execAgentBrowser(`open "${url}"`, 30000);
    execAgentBrowser(`screenshot "${screenshotPath}"`, 30000);
    execAgentBrowser('close', 30000);

    return performVisualAssertion(screenshotPath, criteria, intelligence);
  } catch (error) {
    return {
      pass: false,
      feedback: `Failed to capture page: ${error instanceof Error ? error.message : String(error)}`,
      screenshotPath,
    };
  }
}

/**
 * Quick responsive design check across viewports
 */
export async function assertResponsiveDesign(
  url: string,
  criteria: string,
  viewports: Viewport[] = [VIEWPORTS.desktop, VIEWPORTS.tablet, VIEWPORTS.mobile]
): Promise<VisualAssertionResult[]> {
  const outputDir = './tmp/visual-testing';
  ensureDir(outputDir);

  const results: VisualAssertionResult[] = [];

  try {
    execAgentBrowser(`open "${url}"`, 30000);

    for (const viewport of viewports) {
      execAgentBrowser(`resize ${viewport.width} ${viewport.height}`, 30000);
      await new Promise((resolve) => setTimeout(resolve, 500));

      const screenshotPath = path.join(
        outputDir,
        generateScreenshotName(`responsive-${viewport.name}`)
      );
      execAgentBrowser(`screenshot "${screenshotPath}"`, 30000);

      const fullCriteria = `Responsive (${viewport.name}): ${criteria}`;
      const result = await performVisualAssertion(screenshotPath, fullCriteria, 'smart');
      results.push(result);
    }

    execAgentBrowser('close', 30000);
    return results;
  } catch (error) {
    return [
      {
        pass: false,
        feedback: `Failed responsive check: ${error instanceof Error ? error.message : String(error)}`,
      },
    ];
  }
}

/**
 * Quick accessibility check of a page
 */
export async function assertPageAccessibility(
  url: string,
  criteria: string = 'WCAG AA compliance'
): Promise<VisualAssertionResult> {
  const outputDir = './tmp/visual-testing';
  ensureDir(outputDir);

  const screenshotPath = path.join(outputDir, generateScreenshotName('accessibility'));

  try {
    execAgentBrowser(`open "${url}"`, 30000);
    execAgentBrowser(`screenshot "${screenshotPath}"`, 30000);

    let a11yTree = '';
    try {
      a11yTree = execAgentBrowser('accessibility', 30000);
    } catch {
      // a11y tree not available
    }

    execAgentBrowser('close', 30000);

    const fullCriteria = `Accessibility: ${criteria}. Check color contrast, focus indicators, semantic structure, alt text.${a11yTree ? `\n\nAccessibility Tree:\n${a11yTree}` : ''}`;

    return performVisualAssertion(screenshotPath, fullCriteria, 'smart');
  } catch (error) {
    return {
      pass: false,
      feedback: `Failed accessibility check: ${error instanceof Error ? error.message : String(error)}`,
      screenshotPath,
    };
  }
}

/**
 * Update baseline for a specific test
 */
export function updateBaseline(name: string, outputDir: string = './tmp/visual-testing'): void {
  const currentPath = path.join(outputDir, `${name}-current.png`);
  const baselineDir = path.join(outputDir, 'baselines');
  const baselinePath = path.join(baselineDir, `${name}.png`);

  if (!fs.existsSync(currentPath)) {
    throw new Error(`Current screenshot not found: ${currentPath}`);
  }

  ensureDir(baselineDir);
  fs.copyFileSync(currentPath, baselinePath);
}
