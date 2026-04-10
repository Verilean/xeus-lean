/**
 * DOM → JSON serializer for snapshot testing.
 *
 * Runs inside the browser via `page.evaluate`, so it must be self-
 * contained (no imports, no TypeScript-only features that don't
 * survive stringification). We therefore export it as a plain
 * `Function`-shaped constant.
 *
 * Design goals:
 *
 * 1. **Stable across runs.** JupyterLab generates random IDs and
 *    MathJax writes inline styles with computed pixel sizes — both
 *    are stripped.
 * 2. **Readable in git diff.** Output is a plain JSON tree:
 *    `{ tag, attrs, children }`. Text nodes become
 *    `{ type: 'text', value }`.
 * 3. **Configurable.** Callers can extend the volatile-attribute and
 *    volatile-tag lists via an options object.
 */

export type SerializedNode =
  | { type: 'text'; value: string }
  | {
      tag: string;
      attrs?: Record<string, string>;
      children?: SerializedNode[];
    };

export interface SerializeOptions {
  /** Extra attribute names to strip (merged with the default list). */
  extraVolatileAttrs?: string[];
  /** Extra tags to drop entirely (merged with the default list). */
  extraVolatileTags?: string[];
}

/**
 * The browser-side serializer. Stringified and shipped through
 * `page.evaluate`, so it must not reference any outer scope.
 */
export const browserSerializer = function serializeDom(
  rootSelector: string,
  opts: { volatileAttrs: string[]; volatileTags: string[] }
): unknown {
  const root = document.querySelector(rootSelector);
  if (!root) return null;

  const VOLATILE_ATTRS = new Set(opts.volatileAttrs);
  const VOLATILE_TAGS = new Set(opts.volatileTags.map((t) => t.toLowerCase()));

  // class tokens that look auto-generated: "ui-id-123", "css-1a2b3c",
  // "mjx-n-7", "jp-id-4f5e", etc. Kept coarse on purpose.
  const AUTO_CLASS = /^(?:ui-id-\d+|css-[a-z0-9]+|mjx-[a-z]-\d+|jp-id-[a-z0-9-]+)$/i;

  function normalizeClass(raw: string): string {
    return raw
      .split(/\s+/)
      .filter((c) => c && !AUTO_CLASS.test(c))
      .sort()
      .join(' ');
  }

  function walk(node: Node): unknown {
    if (node.nodeType === 3 /* TEXT_NODE */) {
      const t = (node.textContent ?? '').replace(/\s+/g, ' ').trim();
      return t ? { type: 'text', value: t } : null;
    }
    if (node.nodeType !== 1 /* ELEMENT_NODE */) return null;

    const el = node as Element;
    const tag = el.tagName.toLowerCase();
    if (VOLATILE_TAGS.has(tag)) return null;

    const attrs: Record<string, string> = {};
    for (let i = 0; i < el.attributes.length; i++) {
      const a = el.attributes[i]!;
      if (VOLATILE_ATTRS.has(a.name)) continue;
      if (a.name.startsWith('data-lm-')) continue; // Lumino internals
      if (a.name.startsWith('aria-owns')) continue;
      if (a.name === 'class') {
        const c = normalizeClass(a.value);
        if (c) attrs.class = c;
      } else {
        attrs[a.name] = a.value;
      }
    }

    const children: unknown[] = [];
    for (let i = 0; i < el.childNodes.length; i++) {
      const c = walk(el.childNodes[i]!);
      if (c) children.push(c);
    }

    const out: Record<string, unknown> = { tag };
    if (Object.keys(attrs).length) out.attrs = attrs;
    if (children.length) out.children = children;
    return out;
  }

  return walk(root);
};

/** Attributes stripped by default. */
export const DEFAULT_VOLATILE_ATTRS = [
  'id',
  'style',
  'tabindex',
  'aria-labelledby',
  'aria-describedby',
  'aria-owns',
  'aria-activedescendant',
  'data-jp-suppress-context-menu',
  'data-jp-theme-light',
  'data-jp-theme-name',
  // MathJax bookkeeping
  'jax',
  'data-mjx-texclass',
];

/** Tags dropped entirely by default. */
export const DEFAULT_VOLATILE_TAGS = ['script', 'style'];

/** Build the (volatileAttrs, volatileTags) payload for the browser. */
export function buildOptions(opts: SerializeOptions = {}) {
  return {
    volatileAttrs: [
      ...DEFAULT_VOLATILE_ATTRS,
      ...(opts.extraVolatileAttrs ?? []),
    ],
    volatileTags: [
      ...DEFAULT_VOLATILE_TAGS,
      ...(opts.extraVolatileTags ?? []),
    ],
  };
}
