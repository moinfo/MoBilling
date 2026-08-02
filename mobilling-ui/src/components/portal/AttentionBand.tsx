import { useNavigate } from 'react-router-dom';
import classes from './AttentionBand.module.css';

/**
 * "Needs your attention" — the point of the dashboard redesign.
 *
 * What the customer must act on leads the page instead of sitting below a row
 * of stat tiles. Renders nothing when there is nothing to act on: an empty
 * amber band trains people to ignore the real one.
 *
 * Deliberately does NOT show an amount owed. The dashboard endpoint returns
 * total_balance = total_invoiced - total_paid, which for accounts with
 * migrated payment history can be negative (in credit) while individual
 * invoices are still flagged overdue — so the figure contradicts the count.
 * Until the portal exposes a per-invoice balance, the count and the age are
 * the only numbers here that are certainly true.
 */
interface Props {
  data: {
    overdue_count?: number;
    unpaid_invoices_count?: number;
    expiring_domains_count?: number;
  };
}

export function AttentionBand({ data }: Props) {
  const navigate = useNavigate();

  const overdue = data.overdue_count ?? 0;
  const unpaid = data.unpaid_invoices_count ?? 0;
  const expiring = data.expiring_domains_count ?? 0;

  if (!overdue && !unpaid && !expiring) return null;

  return (
    <div className={classes.band}>
      <div className={classes.head}>
        <span className={classes.dot} aria-hidden="true" />
        NEEDS YOUR ATTENTION
      </div>

      <div className={classes.cards}>
        {(overdue > 0 || unpaid > 0) && (
          <div className={classes.card}>
            <div className={classes.cardBody}>
              <div className={classes.cardTitle}>
                {overdue > 0
                  ? `${overdue} ${overdue === 1 ? 'invoice is' : 'invoices are'} overdue`
                  : `${unpaid} unpaid ${unpaid === 1 ? 'invoice' : 'invoices'}`}
              </div>
              <div className={classes.cardMeta}>
                {unpaid > overdue
                  ? `${unpaid} unpaid in total · settle to keep services active`
                  : 'Settle these to keep your services active'}
              </div>
            </div>
            <button
              type="button"
              className={`${classes.action} ${classes.actionWarn}`}
              onClick={() => navigate('/portal/invoices')}
            >
              View invoices
            </button>
          </div>
        )}

        {expiring > 0 && (
          <div className={classes.card}>
            <div className={classes.cardBody}>
              <div className={classes.cardTitle}>
                {expiring} {expiring === 1 ? 'domain expires' : 'domains expire'} soon
              </div>
              <div className={classes.cardMeta}>
                Within the next 45 days · renew to avoid losing the name
              </div>
            </div>
            <button
              type="button"
              className={`${classes.action} ${classes.actionOk}`}
              onClick={() => navigate('/portal/domains')}
            >
              Renew
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
