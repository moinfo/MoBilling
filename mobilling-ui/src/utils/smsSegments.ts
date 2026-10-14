// Mirrors MoSmS's own SmsGatewayService::countSegments() exactly (the formula
// that actually determines how many credits a send is billed) — GSM-7 messages
// get 160 chars in one segment then 153/segment after that; a single
// non-GSM-7 character (emoji, etc.) switches the whole message to Unicode
// (UCS-2) billing, which is 70 then 67/segment — a much smaller budget.
const GSM_7_CHARS =
  '@£$¥èéùìòÇ\nØøÅåΔ_ΦΓΛΩΠΨΣΘΞ ÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  + 'ÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà\r^{}\\[~]|€';

export function countSmsSegments(text: string): number {
  if (!text) return 1;

  const chars = Array.from(text);
  const isUnicode = chars.some((ch) => !GSM_7_CHARS.includes(ch));
  const length = chars.length;

  if (isUnicode) {
    return length <= 70 ? 1 : Math.ceil(length / 67);
  }

  return length <= 160 ? 1 : Math.ceil(length / 153);
}
