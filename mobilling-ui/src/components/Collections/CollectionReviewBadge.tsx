import { Badge, Tooltip } from '@mantine/core';
import { formatDate } from '../../utils/formatDate';

interface Props {
  reviewedAt?: string | null;
  reviewedByName?: string | null;
  notes?: string | null;
  size?: string;
}

/** Compact "Collection review" status: approved by NAME on DATE (notes in tooltip) or "Not reviewed". */
export default function CollectionReviewBadge({ reviewedAt, reviewedByName, notes, size = 'sm' }: Props) {
  if (!reviewedAt) {
    return <Badge color="gray" variant="light" size={size}>Not reviewed</Badge>;
  }
  const label = `Approved${reviewedByName ? ` by ${reviewedByName}` : ''} · ${formatDate(reviewedAt)}`;
  return (
    <Tooltip label={notes || 'No review notes'} multiline maw={260} withArrow>
      <Badge color="green" variant="light" size={size}>{label}</Badge>
    </Tooltip>
  );
}
