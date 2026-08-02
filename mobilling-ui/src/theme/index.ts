import { createTheme } from '@mantine/core';

/**
 * Portal theme, aligned to the Control Room redesign.
 *
 * Applying the type system and radii here means every existing screen — the
 * invoice tables, the ticket forms, the reports — picks up the redesign
 * without being rewritten one at a time. Per-screen work then only has to
 * handle layout, not typography.
 *
 * Colour values live in src/theme/tokens.css; this maps the ones Mantine needs
 * to know about so components like Button and Badge resolve correctly.
 */
export const theme = createTheme({
  fontFamily: '"Space Grotesk", -apple-system, BlinkMacSystemFont, sans-serif',
  fontFamilyMonospace: '"JetBrains Mono", ui-monospace, monospace',
  headings: {
    fontFamily: '"Space Grotesk", -apple-system, BlinkMacSystemFont, sans-serif',
    fontWeight: '600',
  },
  defaultRadius: 'md',
  radius: {
    xs: '4px',
    sm: '6px',
    md: '8px',
    lg: '12px',
    xl: '20px',
  },
  components: {
    // Tables carry most of the portal's data, so tabular figures matter more
    // here than anywhere else — columns of money must line up.
    Table: {
      styles: {
        td: { fontVariantNumeric: 'tabular-nums' },
      },
    },
  },
});
