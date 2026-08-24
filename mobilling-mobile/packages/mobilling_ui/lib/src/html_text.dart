/// Minimal HTML → readable plain text, for tenant-authored content
/// (announcements, knowledgebase articles).
///
/// A full HTML renderer is deliberately avoided: these bodies come from a
/// simple rich-text editor (paragraphs, lists, bold, links), and a heavyweight
/// webview/HTML dependency for that trade-off isn't worth it in v1. Block
/// tags become line breaks, list items become bullets, entities are decoded,
/// everything else is stripped.
String htmlToPlainText(String html) {
  if (html.isEmpty) return '';

  var text = html
      // Line-break producing tags first, so structure survives the strip.
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</p>|</div>|</h[1-6]>', caseSensitive: false),
        '\n\n',
      )
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(RegExp(r'</(ul|ol)>', caseSensitive: false), '\n')
      // Everything else goes.
      .replaceAll(RegExp(r'<[^>]+>'), '');

  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&mdash;': '—',
    '&ndash;': '–',
  };
  entities.forEach((entity, char) => text = text.replaceAll(entity, char));

  // Numeric entities (&#8211; etc.).
  text = text.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m.group(1)!)),
  );

  // Collapse the whitespace debris stripping leaves behind.
  return text
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
