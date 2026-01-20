/**
 * Visual Testing Library - Test Examples
 *
 * These examples show Ralph how to use visual-testing for UI verification.
 * Ralph discovers these patterns during src/lib exploration.
 *
 * IMPORTANT: These tests require:
 * - agent-browser installed globally (npm install -g agent-browser)
 * - A running application server
 * - The ANTHROPIC_API_KEY environment variable set
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import {
  VisualTestContext,
  createVisualTestSession,
  assertPageVisual,
  assertResponsiveDesign,
  assertPageAccessibility,
  VIEWPORTS,
  VisualAssertionResult,
} from './visual-testing.js';
import * as fs from 'fs';

// =============================================================================
// Test Configuration
// =============================================================================

const TEST_BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:3000';
const SKIP_VISUAL_TESTS = process.env.SKIP_VISUAL_TESTS === 'true';

// Helper to skip tests when visual testing dependencies aren't available
function skipIfNoVisualTesting() {
  if (SKIP_VISUAL_TESTS) {
    console.log('Skipping: SKIP_VISUAL_TESTS=true');
    return true;
  }
  return false;
}

// =============================================================================
// Layout and Hierarchy Tests
// =============================================================================

describe('Layout and visual hierarchy', () => {
  let session: VisualTestContext;

  beforeAll(async () => {
    if (skipIfNoVisualTesting()) return;
    session = await createVisualTestSession({ baseUrl: TEST_BASE_URL });
  });

  afterAll(async () => {
    if (session) await session.close();
  });

  it('verifies dashboard visual hierarchy', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/dashboard');
    const result = await session.assertLayout(
      'Clear visual hierarchy with primary action prominent; navigation easily discoverable; content organized in logical groups'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies landing page layout', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/');
    const result = await session.assertLayout(
      'Hero section draws attention; clear value proposition above the fold; obvious call-to-action'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies spacing consistency', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/settings');
    const result = await session.assertSpacing(
      'Consistent spacing between form groups; adequate padding within cards; visual rhythm maintained'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies alignment and grid', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/products');
    const result = await session.assertAlignment(
      'Product cards aligned to consistent grid; images same size; text aligned within cards'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });
});

// =============================================================================
// Responsive Design Tests
// =============================================================================

describe('Responsive design', () => {
  let session: VisualTestContext;

  beforeAll(async () => {
    if (skipIfNoVisualTesting()) return;
    session = await createVisualTestSession({ baseUrl: TEST_BASE_URL });
  });

  afterAll(async () => {
    if (session) await session.close();
  });

  it('verifies responsive layout across viewports', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/');
    const results = await session.assertResponsive(
      'Content readable; no horizontal scroll; touch targets appropriately sized; images scale properly',
      [VIEWPORTS.desktop, VIEWPORTS.tablet, VIEWPORTS.mobile]
    );

    results.forEach((result: VisualAssertionResult, index: number) => {
      expect(result.pass).toBe(true);
      if (!result.pass) {
        console.log(`Viewport ${index} feedback:`, result.feedback);
      }
    });
  });

  it('verifies mobile-specific criteria', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/dashboard');
    const result = await session.assertMobile(
      'Navigation collapsed to hamburger menu; cards stack vertically; buttons full-width for easy tapping'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies tablet layout', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.setViewport(VIEWPORTS.tablet);
    await session.navigate('/products');

    const result = await session.assertVisual(
      'tablet-products',
      'Products display in 2-column grid; sidebar visible but compact; adequate touch targets'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });
});

// =============================================================================
// Component State Tests
// =============================================================================

describe('Interactive states', () => {
  let session: VisualTestContext;

  beforeAll(async () => {
    if (skipIfNoVisualTesting()) return;
    session = await createVisualTestSession({ baseUrl: TEST_BASE_URL });
  });

  afterAll(async () => {
    if (session) await session.close();
  });

  it('verifies button hover state', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/');
    const result = await session.assertInteractiveState({
      target: 'button.primary',
      state: 'hover',
      criteria: 'Hover state clearly visible with color change or shadow; cursor indicates clickability',
    });

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies input focus state', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/login');
    const result = await session.assertInteractiveState({
      target: 'input[type="email"]',
      state: 'focus',
      criteria: 'Focus ring clearly visible; high contrast against background; indicates active input',
    });

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies disabled button state', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/checkout');
    const result = await session.assertInteractiveState({
      target: 'button[disabled]',
      state: 'disabled',
      criteria: 'Disabled state obvious via reduced opacity or grayed appearance; cursor indicates non-interactive',
    });

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });
});

// =============================================================================
// Accessibility Tests
// =============================================================================

describe('Accessibility', () => {
  let session: VisualTestContext;

  beforeAll(async () => {
    if (skipIfNoVisualTesting()) return;
    session = await createVisualTestSession({ baseUrl: TEST_BASE_URL });
  });

  afterAll(async () => {
    if (session) await session.close();
  });

  it('verifies color contrast meets WCAG AA', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/');
    const result = await session.assertAccessibility(
      'All text has sufficient contrast ratio (4.5:1 for normal text, 3:1 for large text); no information conveyed by color alone'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies keyboard navigation flow', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/');
    const result = await session.assertKeyboardNavigation(
      [
        { key: 'Tab', expectedFocus: 'a.logo' },
        { key: 'Tab', expectedFocus: 'a.nav-link' },
        { key: 'Tab', expectedFocus: 'button.cta' },
      ],
      'Focus moves in logical order; skip link available; focus visible at each step'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies form accessibility', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/contact');
    const result = await session.assertAccessibility(
      'Form inputs have visible labels; error states clearly indicated; required fields marked'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });
});

// =============================================================================
// Baseline Regression Tests
// =============================================================================

describe('Visual regression', () => {
  let session: VisualTestContext;

  beforeAll(async () => {
    if (skipIfNoVisualTesting()) return;
    session = await createVisualTestSession({ baseUrl: TEST_BASE_URL });
  });

  afterAll(async () => {
    if (session) await session.close();
  });

  it('verifies homepage matches baseline', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/');
    const result = await session.assertBaseline(
      'homepage',
      'Layout and major elements unchanged; minor text updates acceptable; no missing images or broken styles'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies component library matches baseline', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/storybook');
    const result = await session.assertBaseline(
      'component-library',
      'Component styles unchanged; no unintended visual regressions; spacing preserved'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });
});

// =============================================================================
// Quick Check Examples (One-off without session)
// =============================================================================

describe('Quick visual checks', () => {
  it('performs one-off page visual check', async () => {
    if (skipIfNoVisualTesting()) return;

    const result = await assertPageVisual(
      `${TEST_BASE_URL}/about`,
      'Professional appearance; clear typography; consistent branding'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('performs quick responsive check', async () => {
    if (skipIfNoVisualTesting()) return;

    const results = await assertResponsiveDesign(
      `${TEST_BASE_URL}/pricing`,
      'Pricing cards readable; no overlap; amounts clearly visible'
    );

    results.forEach((result: VisualAssertionResult) => {
      expect(result.pass).toBe(true);
      if (!result.pass) console.log('Feedback:', result.feedback);
    });
  });

  it('performs quick accessibility check', async () => {
    if (skipIfNoVisualTesting()) return;

    const result = await assertPageAccessibility(
      `${TEST_BASE_URL}/`,
      'WCAG AA compliance; semantic HTML; keyboard accessible'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });
});

// =============================================================================
// Typography and Colors Tests
// =============================================================================

describe('Typography and colors', () => {
  let session: VisualTestContext;

  beforeAll(async () => {
    if (skipIfNoVisualTesting()) return;
    session = await createVisualTestSession({ baseUrl: TEST_BASE_URL });
  });

  afterAll(async () => {
    if (session) await session.close();
  });

  it('verifies typography hierarchy', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/blog/sample-post');
    const result = await session.assertTypography(
      'Clear heading hierarchy (h1 > h2 > h3); readable body text size; adequate line height for readability'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });

  it('verifies color consistency', async () => {
    if (skipIfNoVisualTesting()) return;

    await session.navigate('/');
    const result = await session.assertColors(
      'Consistent brand colors throughout; accent colors used purposefully; no jarring color combinations'
    );

    expect(result.pass).toBe(true);
    if (!result.pass) console.log('Feedback:', result.feedback);
  });
});
