/** Shared badge colors for Followup outcome/status — used by Followups.tsx and the Invoices follow-up column/modal. */
export const outcomeColors: Record<string, string> = {
  promised: 'blue',
  declined: 'red',
  no_answer: 'gray',
  disputed: 'orange',
  partial_payment: 'yellow',
};

export const outcomeLabels: Record<string, string> = {
  promised: 'Promised to pay',
  declined: 'Declined',
  no_answer: 'No answer',
  disputed: 'Disputed',
  partial_payment: 'Partial payment',
};

export const statusColors: Record<string, string> = {
  pending: 'blue',
  open: 'cyan',
  fulfilled: 'green',
  broken: 'red',
  escalated: 'orange',
  cancelled: 'gray',
};
