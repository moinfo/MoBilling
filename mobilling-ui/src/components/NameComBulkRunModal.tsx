import { useEffect, useRef, useState } from 'react';
import { Modal, Stack, Progress, Text, Group, Button, Alert, List, Badge } from '@mantine/core';
import { bulkSyncNameCom, bulkRegistrarLookup } from '../api/domains';

type Kind = 'sync' | 'lookup';

/** Staff-only: drives a chunked, server-paced bulk action and shows progress + a result summary. */
export default function NameComBulkRunModal({ kind, onClose, onDone }: { kind: Kind; onClose: () => void; onDone: () => void }) {
  const [running, setRunning] = useState(true);
  const [done, setDone] = useState(0);
  const [total, setTotal] = useState(0);
  const [sum, setSum] = useState({ updated: 0, unchanged: 0, failed: 0, skipped: 0, checked: 0, skipped_fresh: 0, at_namecom: 0, other: 0, unknown: 0 });
  const [failures, setFailures] = useState<{ domain: string; reason: string }[]>([]);
  const [error, setError] = useState<string | null>(null);
  const cancelled = useRef(false);
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    (async () => {
      let cursor: string | null = null;
      try {
        do {
          const res: any = kind === 'sync' ? await bulkSyncNameCom(cursor) : await bulkRegistrarLookup(cursor);
          const c = res.data.data;
          cursor = c.next;
          setTotal(c.total);
          setDone((d) => d + c.processed);
          setSum((s) => ({
            updated: s.updated + (c.updated ?? 0), unchanged: s.unchanged + (c.unchanged ?? 0), failed: s.failed + (c.failed ?? 0), skipped: s.skipped + (c.skipped ?? 0),
            checked: s.checked + (c.checked ?? 0), skipped_fresh: s.skipped_fresh + (c.skipped_fresh ?? 0),
            at_namecom: s.at_namecom + (c.at_namecom ?? 0), other: s.other + (c.other ?? 0), unknown: s.unknown + (c.unknown ?? 0),
          }));
          if (c.failures?.length) setFailures((f) => [...f, ...c.failures].slice(0, 60));
        } while (cursor && !cancelled.current);
      } catch (e: any) {
        setError(e?.response?.status === 429 ? 'Too many requests - wait a minute and try again.' : (e?.response?.data?.message ?? 'The run stopped unexpectedly. Already-processed domains were saved.'));
      } finally {
        setRunning(false);
        onDone();
      }
    })();
  }, []); // eslint-disable-line

  const pct = total ? Math.round((done / total) * 100) : 0;
  return (
    <Modal opened onClose={() => { cancelled.current = true; onClose(); }} size="lg"
      title={kind === 'sync' ? 'Sync Name.com domains' : 'Check registrar (public lookup)'} closeOnClickOutside={!running}>
      <Stack gap="sm">
        <Text size="sm" c="dimmed">
          {kind === 'sync'
            ? 'Refreshing expiry, status, nameservers, lock, auto-renew and privacy from Name.com. Read-only: nothing is changed at Name.com and nothing is charged.'
            : 'Looking up the sponsoring registrar in the public registry (RDAP) for .com/.net/.org domains that are not linked. Each domain is re-checked at most once a week.'}
        </Text>
        <Progress value={pct} animated={running} />
        <Text size="xs" c="dimmed">{done} of {total || '...'} domains {running ? 'processed...' : 'processed'}</Text>
        {kind === 'sync' ? (
          <Group gap="xs">
            <Badge color="green" variant="light">{sum.updated} updated</Badge>
            <Badge color="gray" variant="light">{sum.unchanged} unchanged</Badge>
            <Badge color="red" variant="light">{sum.failed} failed</Badge>
            <Badge color="yellow" variant="light">{sum.skipped} skipped</Badge>
          </Group>
        ) : (
          <Group gap="xs">
            <Badge color="blue" variant="light">{sum.at_namecom} at Name.com</Badge>
            <Badge color="gray" variant="light">{sum.other} at other registrars</Badge>
            <Badge color="yellow" variant="light">{sum.unknown} unknown</Badge>
            <Badge color="teal" variant="light">{sum.skipped_fresh} recently checked</Badge>
          </Group>
        )}
        {error && <Alert color="red" variant="light">{error}</Alert>}
        {failures.length > 0 && (
          <Alert color="orange" variant="light" title="Needs attention">
            <List size="xs" spacing={2}>
              {failures.map((f, i) => <List.Item key={i}><b>{f.domain}</b>: {f.reason}</List.Item>)}
            </List>
          </Alert>
        )}
        <Group justify="flex-end">
          <Button variant="light" onClick={() => { cancelled.current = true; onClose(); }}>{running ? 'Stop' : 'Close'}</Button>
        </Group>
      </Stack>
    </Modal>
  );
}
