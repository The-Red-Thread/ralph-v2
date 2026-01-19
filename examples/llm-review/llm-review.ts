/**
 * LLM-as-Judge Review Library
 *
 * Enables non-deterministic backpressure for subjective acceptance criteria:
 * tone, aesthetics, UX intuitiveness, brand consistency.
 *
 * Usage:
 *   import { createReview } from './llm-review';
 *
 *   const result = await createReview({
 *     criteria: 'Warm, conversational tone',
 *     artifact: textContent,
 *   });
 *
 *   expect(result.pass).toBe(true);
 */

import Anthropic from '@anthropic-ai/sdk';
import * as fs from 'fs';
import * as path from 'path';

// =============================================================================
// Types
// =============================================================================

export interface ReviewConfig {
  /**
   * Observable behavioral outcome to evaluate.
   * Be specific: "Warm, conversational tone for design professionals"
   * not "Good writing"
   */
  criteria: string;

  /**
   * Content to evaluate: text string or path to image file.
   * Image paths should end in .png, .jpg, .jpeg, .gif, or .webp
   */
  artifact: string;

  /**
   * Intelligence level for evaluation.
   * - 'fast': Quick evaluation, good for simple criteria
   * - 'smart': Deeper analysis, better for nuanced judgment
   * Default: 'fast'
   */
  intelligence?: 'fast' | 'smart';
}

export interface ReviewResult {
  /** Whether the artifact passes the criteria */
  pass: boolean;

  /** Feedback explaining why it failed (only present when pass=false) */
  feedback?: string;
}

// =============================================================================
// Implementation
// =============================================================================

const client = new Anthropic();

/**
 * Detect if artifact is an image path
 */
function isImagePath(artifact: string): boolean {
  const imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];
  const ext = path.extname(artifact).toLowerCase();
  return imageExtensions.includes(ext) && fs.existsSync(artifact);
}

/**
 * Read image file and convert to base64
 */
function readImageAsBase64(imagePath: string): { data: string; mediaType: string } {
  const buffer = fs.readFileSync(imagePath);
  const data = buffer.toString('base64');

  const ext = path.extname(imagePath).toLowerCase();
  const mediaTypes: Record<string, string> = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
  };

  return {
    data,
    mediaType: mediaTypes[ext] || 'image/png',
  };
}

/**
 * Get model based on intelligence level
 */
function getModel(intelligence: 'fast' | 'smart'): string {
  return intelligence === 'smart'
    ? 'claude-sonnet-4-20250514'  // More capable for nuanced judgment
    : 'claude-haiku-4-20250514';  // Fast for simple criteria
}

/**
 * Create a review evaluating an artifact against criteria.
 * Returns binary pass/fail with feedback on failure.
 */
export async function createReview(config: ReviewConfig): Promise<ReviewResult> {
  const { criteria, artifact, intelligence = 'fast' } = config;

  const systemPrompt = `You are a quality reviewer evaluating content against specific criteria.

Your task:
1. Evaluate the provided content against the criteria
2. Return a JSON response with exactly this format:
   {"pass": true} or {"pass": false, "feedback": "specific reason for failure"}

Rules:
- Be strict but fair in evaluation
- Only pass if criteria are clearly met
- Feedback should be actionable and specific
- Do not explain your reasoning outside the JSON
- Return ONLY the JSON, no other text`;

  const userPrompt = `Criteria: ${criteria}

Evaluate this content and return JSON:`;

  let messages: Anthropic.MessageParam[];

  if (isImagePath(artifact)) {
    const { data, mediaType } = readImageAsBase64(artifact);
    messages = [{
      role: 'user',
      content: [
        { type: 'text', text: userPrompt },
        {
          type: 'image',
          source: {
            type: 'base64',
            media_type: mediaType as 'image/png' | 'image/jpeg' | 'image/gif' | 'image/webp',
            data
          }
        },
      ],
    }];
  } else {
    messages = [{
      role: 'user',
      content: `${userPrompt}\n\n${artifact}`,
    }];
  }

  const response = await client.messages.create({
    model: getModel(intelligence),
    max_tokens: 256,
    system: systemPrompt,
    messages,
  });

  // Extract text from response
  const text = response.content
    .filter((block): block is Anthropic.TextBlock => block.type === 'text')
    .map(block => block.text)
    .join('');

  // Parse JSON response
  try {
    const result = JSON.parse(text.trim());
    return {
      pass: Boolean(result.pass),
      feedback: result.pass ? undefined : result.feedback,
    };
  } catch {
    // If parsing fails, treat as failure
    return {
      pass: false,
      feedback: `Failed to parse review response: ${text}`,
    };
  }
}

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Quick text review with fast intelligence
 */
export async function reviewText(
  text: string,
  criteria: string
): Promise<ReviewResult> {
  return createReview({ criteria, artifact: text, intelligence: 'fast' });
}

/**
 * Image review with smart intelligence (default for visual judgment)
 */
export async function reviewImage(
  imagePath: string,
  criteria: string
): Promise<ReviewResult> {
  return createReview({ criteria, artifact: imagePath, intelligence: 'smart' });
}

/**
 * Strict review requiring smart intelligence
 */
export async function reviewStrict(
  artifact: string,
  criteria: string
): Promise<ReviewResult> {
  return createReview({ criteria, artifact, intelligence: 'smart' });
}
