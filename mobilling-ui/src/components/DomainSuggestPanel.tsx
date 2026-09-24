import { useEffect, useRef, useState } from 'react';
import { Stack, Group, Text, TextInput, Button, Badge, Paper, Loader, Alert, Tooltip, UnstyledButton } from '@mantine/core';
import { IconSearch, IconCheck, IconX, IconAlertTriangle, IconStar } from '@tabler/icons-react';
import type { DomainSuggestFn, DomainSuggestRow } from '../api/domains';

const tzs = (v: number | null) => (v === null || v === undefined ? '' : `TZS ${Number(v).toLocaleString('en-US', { maximumFractionDigits: 0 })}`);
const CONCURRENCY = 3;

/** Bare name ("acme") or name + TLD ("acme.com") -> label / typed TLD. */
const parseInput = (s: string) => {
  const v = s.trim().toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').split('/')[0];
  const i = v.indexOf('.');
  return i < 0 ? { label: v, tld: '' } : { label: v.slice(0, i), tld: v.slice(i + 1) };
};

/**
 * Domain search: shows the typed TLD first, then the popular TLDs on sale, each with availability,
 * TZS price and an order button. Rows appear immediately (no lookups), then availability fills in
 * progressively: every "batch" row in one request, the others one per request (limited concurrency).
 */
export default function DomainSuggestPanel({ suggest, onSelect, actionLabel = 'Order', placeholder = 'Type a name, e.g. mybusiness or mybusiness.com', initialQuery = '', staff = false }: {
  suggest: DomainSuggestFn;
  onSelect: (row: DomainSuggestRow) => void;
  actionLabel?: string;
  placeholder?: string;
  initialQuery?: string;
  staff?: boolean;
}) {
  const [input, setInput] = useState(initialQuery);
  const [rows, setRows] = useState<DomainSuggestRow[]>([]);
  const [popular, setPopular] = useState<DomainSuggestRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const run = useRef(0);
  const inputRef = useRef<HTMLInputElement>(null);

  // popular chips (prices only, no lookups)
  useEffect(() => {
    let alive = true;
    suggest('example', { check: false }).then((r) => { if (alive) setPopular(r.filter((x) => x.offered && x.popular).slice(0, 10)); }).catch(() => undefined);
    return () => { alive = false; };
  }, [suggest]);

  const merge = (id: number, upd: DomainSuggestRow[]) => {
    if (id !== run.current) return;
    setRows((cur) => cur.map((r) => upd.find((u) => u.tld === r.tld) ?? r));
  };

  const search = async (text = input) => {
    const { label } = parseInput(text);
    if (!label) return;
    const id = ++run.current;
    setError(null); setBusy(true);
    try {
      const plan = await suggest(text.trim(), { check: false });
      if (id !== run.current) return;
      setRows(plan);
      const pending = plan.filter((r) => r.status === 'pending');
      const batch = pending.filter((r) => r.check_group === 'batch').map((r) => r.tld);
      const single = pending.filter((r) => r.check_group !== 'batch').map((r) => r.tld);
      const jobs: Array<() => Promise<void>> = [];
      if (batch.length) jobs.push(async () => merge(id, await suggest(text.trim(), { tlds: batch })));
      single.forEach((t) => jobs.push(async () => merge(id, await suggest(text.trim(), { tlds: [t] }))));
      let next = 0;
      const worker = async () => {
        while (next < jobs.length) {
          const job = jobs[next++];
          try { await job(); } catch {
            if (id === run.current) setRows((cur) => cur.map((r) => (r.status === 'pending' ? { ...r, status: 'cannot_check' } : r)));
          }
        }
      };
      await Promise.all(Array.from({ length: Math.min(CONCURRENCY, jobs.length) }, worker));
    } catch (e: any) {
      if (id === run.current) setError(e?.response?.data?.message ?? 'Search failed. Please try again.');
    } finally {
      if (id === run.current) setBusy(false);
    }
  };

  const pickChip = (tld: string) => {
    const { label } = parseInput(input);
    if (!label) {
      setInput(`.${tld}`);
      requestAnimationFrame(() => { inputRef.current?.focus(); inputRef.current?.setSelectionRange(0, 0); });
      return;
    }
    const text = `${label}.${tld}`;
    setInput(text);
    search(text);
  };

  return (
    <Stack gap="xs">
      <Group gap="xs" wrap="nowrap" align="flex-start">
        <TextInput ref={inputRef} style={{ flex: 1 }} placeholder={placeholder} value={input} aria-label="Domain name"
          onChange={(e) => setInput(e.currentTarget.value)} onKeyDown={(e) => { if (e.key === 'Enter') search(); }} />
        <Button leftSection={<IconSearch size={16} />} loading={busy && rows.length === 0} onClick={() => search()}>Search</Button>
      </Group>

      {popular.length > 0 && (
        <Group gap={6}>
          <Text size="xs" c="dimmed">Popular:</Text>
          {popular.map((p) => (
            <Tooltip key={p.tld} label={p.register_price !== null ? `${tzs(p.register_price)} / year` : ''} disabled={p.register_price === null}>
              <UnstyledButton onClick={() => pickChip(p.tld)} aria-label={`Use .${p.tld}`}>
                <Badge variant="light" size="lg" radius="sm" style={{ cursor: 'pointer', textTransform: 'none' }}>
                  .{p.tld}{p.register_price !== null ? ` · ${Number(p.register_price).toLocaleString('en-US', { maximumFractionDigits: 0 })}` : ''}
                </Badge>
              </UnstyledButton>
            </Tooltip>
          ))}
        </Group>
      )}

      {error && <Alert color="red" variant="light">{error}</Alert>}

      {rows.length > 0 && (
        <Stack gap={6} mt={4}>
          {rows.map((r) => <ResultRow key={r.tld} row={r} actionLabel={actionLabel} staff={staff} onSelect={onSelect} />)}
        </Stack>
      )}
    </Stack>
  );
}

function ResultRow({ row, actionLabel, staff, onSelect }: { row: DomainSuggestRow; actionLabel: string; staff: boolean; onSelect: (r: DomainSuggestRow) => void }) {
  const s = row.status;
  const badge =
    s === 'pending' ? <Loader size="xs" /> :
    s === 'available' ? <Badge color="green" variant="light" leftSection={<IconCheck size={12} />}>Available</Badge> :
    s === 'taken' ? <Badge color="red" variant="light" leftSection={<IconX size={12} />}>Taken</Badge> :
    s === 'unavailable' ? <Badge color="gray" variant="light">Not available</Badge> :
    s === 'manual' ? <Badge color="yellow" variant="light">Check manually</Badge> :
    s === 'disabled' ? <Badge color="orange" variant="light" leftSection={<IconAlertTriangle size={12} />}>Not on sale</Badge> :
    s === 'not_offered' ? <Badge color="gray" variant="light">Not offered</Badge> :
    <Badge color="gray" variant="light">Cannot check</Badge>;

  return (
    <Paper withBorder radius="md" p="xs" px="sm" style={row.typed ? { borderColor: 'var(--mantine-color-blue-5)' } : undefined}>
      <Group justify="space-between" wrap="wrap" gap="xs">
        <Group gap="xs" wrap="wrap" style={{ flex: '1 1 220px', minWidth: 0 }}>
          {row.popular && <IconStar size={13} style={{ color: 'var(--mantine-color-yellow-6)' }} />}
          <Text fw={600} style={{ overflowWrap: 'anywhere' }}>{row.name}</Text>
          {badge}
          {staff && row.via === 'manual' && <Badge size="xs" variant="outline" color="gray">manual</Badge>}
        </Group>
        <Group gap="sm" wrap="nowrap">
          {row.offered && row.register_price !== null && <Text size="sm" c="dimmed">{tzs(row.register_price)}/yr</Text>}
          {row.can_order && <Button size="compact-sm" onClick={() => onSelect(row)}>{actionLabel}</Button>}
        </Group>
      </Group>
      {row.message && (s === 'disabled' || s === 'not_offered' || s === 'manual' || s === 'cannot_check') && <Text size="xs" c="dimmed" mt={2}>{row.message}</Text>}
    </Paper>
  );
}
