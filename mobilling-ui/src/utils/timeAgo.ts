import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';

dayjs.extend(relativeTime);

/** "2d ago" / "in 3 days" style relative time. */
export const timeAgo = (date: string | Date): string => dayjs(date).fromNow();
