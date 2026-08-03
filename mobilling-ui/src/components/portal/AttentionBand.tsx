import { useNavigate } from 'react-router-dom';
import { useLanguage } from '../../i18n/LanguageContext';
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
  const { t } = useLanguage();

  const overdue = data.overdue_count ?? 0;
  const unpaid = data.unpaid_invoices_count ?? 0;
  const expiring = data.expiring_domains_count ?? 0;

  if (!overdue && !unpaid && !expiring) return null;

  return (
    <div className={classes.band}>
      <div className={classes.head}>
        <span className={classes.dot} aria-hidden="true" />
        {t('attention.title')}
      </div>

      <div className={classes.cards}>
        {(overdue > 0 || unpaid > 0) && (
          <div className={classes.card}>
            <div className={classes.cardBody}>
              <div className={classes.cardTitle}>
                {overdue > 0
                  ? `${overdue} ${t(overdue === 1 ? 'attention.invoicesOverdueOne' : 'attention.invoicesOverdueMany')}`
                  : `${unpaid} ${t(unpaid === 1 ? 'attention.unpaidOne' : 'attention.unpaidMany')}`}
              </div>
              <div className={classes.cardMeta}>
                {unpaid > overdue
                  ? `${unpaid} ${t('attention.unpaidTotal')}`
                  : t('attention.settleNote')}
              </div>
            </div>
            <button
              type="button"
              className={`${classes.action} ${classes.actionWarn}`}
              onClick={() => navigate('/portal/invoices')}
            >
              {t('attention.viewInvoices')}
            </button>
          </div>
        )}

        {expiring > 0 && (
          <div className={classes.card}>
            <div className={classes.cardBody}>
              <div className={classes.cardTitle}>
                {expiring} {t(expiring === 1 ? 'attention.domainExpiresOne' : 'attention.domainExpiresMany')}
              </div>
              <div className={classes.cardMeta}>
                {t('attention.domainNote')}
              </div>
            </div>
            <button
              type="button"
              className={`${classes.action} ${classes.actionOk}`}
              onClick={() => navigate('/portal/domains')}
            >
              {t('attention.renew')}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
