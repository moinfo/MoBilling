import type { CSSProperties } from 'react';

export function chartTooltipStyle(dark: boolean): CSSProperties {
  return {
    backgroundColor: dark ? '#25262b' : '#ffffff',
    border: `1px solid ${dark ? '#373A40' : '#dee2e6'}`,
    borderRadius: 8,
    color: dark ? '#c1c2c5' : '#212529',
  };
}

export function chartTickStyle(dark: boolean) {
  return { fontSize: 12, fill: dark ? '#909296' : '#868e96' };
}
