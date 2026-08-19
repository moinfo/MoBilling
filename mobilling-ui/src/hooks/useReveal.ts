import { useEffect, useRef } from 'react';

/**
 * Scroll-reveal for the marketing pages.
 *
 * Attach the returned ref to a container; every descendant carrying a
 * `data-reveal` attribute fades and rises as it scrolls into view, staggered
 * by its position among its siblings so a row of cards arrives in sequence.
 *
 * Fail-open is the whole point. The hidden state (`data-reveal="pending"`) is
 * applied here, in the effect, *after* the observer exists — never in the
 * markup. So if IntersectionObserver is missing, the effect never runs, or JS
 * fails outright, the content is simply visible. The alternative — hiding in
 * CSS and revealing in JS — turns any failure into a blank page.
 *
 * @param stagger  Delay per sibling index, in ms.
 */
export function useReveal(stagger = 70) {
  const ref = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const root = ref.current;
    if (!root) return;

    const nodes = Array.from(root.querySelectorAll<HTMLElement>('[data-reveal]'));
    if (nodes.length === 0) return;

    const show = (el: HTMLElement) => {
      el.dataset.reveal = 'shown';
    };

    if (typeof IntersectionObserver === 'undefined') {
      nodes.forEach(show);
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const el = entry.target as HTMLElement;
          show(el);
          observer.unobserve(el); // each element animates once
        }
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.05 },
    );

    for (const el of nodes) {
      // Stagger by position within the element's own row/grid, not globally.
      const index = el.parentElement
        ? Array.from(el.parentElement.children).indexOf(el)
        : 0;
      el.style.transitionDelay = `${Math.min(index, 6) * stagger}ms`;
      el.dataset.reveal = 'pending';
      observer.observe(el);
    }

    return () => observer.disconnect();
  }, [stagger]);

  return ref;
}
