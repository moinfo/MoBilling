import { useState } from 'react';
import { Stack, Group, Text, TextInput, Button, Alert, Loader, Code, Title, Paper, Badge, Modal, List, CopyButton } from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconLock, IconLockOpen, IconKey, IconCopy, IconAlertTriangle } from '@tabler/icons-react';

export interface TransferState {
  locked: boolean | null;
  transfer_lock_until: string | null;
  can_transfer: boolean;
  blocked?: boolean;
  blocked_reason?: string | null;
  client_block?: string | null;
  is_admin?: boolean;
}

const errMsg = (e: any) => e?.response?.data?.message ?? (Object.values(e?.response?.data?.errors ?? {}).flat().join(' ') || 'Something went wrong. Please try again.');

/**
 * Transfer-out readiness (lock state, unlock/lock, one-time transfer authorization code).
 * Shared by the client portal (neutral wording, retype-to-confirm) and staff.
 * The code lives only in component state while the modal is open and is dropped on close.
 */
export default function DomainTransferCard({ queryKey, domainName, fetcher, lock, unlock, getCode, canAct, portal, invalidate = [] }: {
  queryKey: unknown[];
  domainName: string;
  fetcher: () => Promise<{ data: { data: TransferState } }>;
  lock: () => Promise<{ data: { data: TransferState; message: string } }>;
  unlock: (confirm: string) => Promise<{ data: { data: TransferState; message: string } }>;
  getCode: (confirm: string) => Promise<{ data: { auth_code: string } }>;
  canAct: boolean;
  portal?: boolean;
  invalidate?: unknown[][];
}) {
  const qc = useQueryClient();
  const [confirmFor, setConfirmFor] = useState<'unlock' | 'code' | null>(null);
  const [typed, setTyped] = useState('');
  const [code, setCode] = useState<string | null>(null);

  const { data, isLoading, isError, error } = useQuery({ queryKey, queryFn: fetcher, retry: false });
  const s = data?.data?.data;
  const blockedMsg = s?.blocked_reason ?? null;
  const staffNote = !portal ? s?.client_block ?? null : null;
  const refresh = () => { qc.invalidateQueries({ queryKey }); invalidate.forEach((k) => qc.invalidateQueries({ queryKey: k })); };

  const lockM = useMutation({
    mutationFn: () => lock(),
    onSuccess: (r) => { refresh(); notifications.show({ title: 'Done', message: r.data.message, color: 'green' }); },
    onError: (e) => notifications.show({ title: 'Could not lock', message: errMsg(e), color: 'red' }),
  });
  const unlockM = useMutation({
    mutationFn: () => unlock(typed),
    onSuccess: (r) => { refresh(); setConfirmFor(null); setTyped(''); notifications.show({ title: 'Done', message: r.data.message, color: 'green', autoClose: 9000 }); },
    onError: (e) => notifications.show({ title: 'Could not unlock', message: errMsg(e), color: 'red' }),
  });
  const codeM = useMutation({
    mutationFn: () => getCode(typed),
    onSuccess: (r) => { setCode(r.data.auth_code); setConfirmFor(null); setTyped(''); refresh(); },
    onError: (e) => notifications.show({ title: 'Could not get the code', message: errMsg(e), color: 'red' }),
  });

  const typedOk = !portal || typed.trim().toLowerCase() === domainName.toLowerCase();
  const closeConfirm = () => { setConfirmFor(null); setTyped(''); };
  const busy = lockM.isPending || unlockM.isPending || codeM.isPending;

  return (
    <Paper withBorder radius="md" p="lg">
      <Stack gap="md">
        <Group gap="xs"><IconKey size={18} /><Title order={5}>Transfer</Title></Group>
        <Text size="sm" c="dimmed">
          To move this domain to another provider you need to unlock it and get its transfer authorization code.
        </Text>

        {isLoading ? (
          <Group gap="xs"><Loader size="xs" /><Text size="sm" c="dimmed">Checking domain lock...</Text></Group>
        ) : isError || !s ? (
          <Alert color="orange" variant="light">{errMsg(error)}</Alert>
        ) : (
          <>
            <Group gap="xs">
              <Text size="sm" fw={600}>Domain lock:</Text>
              {s.locked === null
                ? <Badge color="gray" variant="light">Unknown</Badge>
                : s.locked
                  ? <Badge color="green" variant="light" leftSection={<IconLock size={12} />}>Locked</Badge>
                  : <Badge color="orange" variant="light" leftSection={<IconLockOpen size={12} />}>Unlocked</Badge>}
              <Badge color={s.can_transfer ? 'orange' : 'gray'} variant="outline">
                {s.can_transfer ? 'Transfer possible' : 'Transfer blocked by lock'}
              </Badge>
            </Group>
            {s.transfer_lock_until && (
              <Alert color="blue" variant="light">
                A mandatory transfer restriction applies until {new Date(s.transfer_lock_until).toLocaleDateString()}. The domain cannot be unlocked before then.
              </Alert>
            )}
            {blockedMsg && <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />}>{blockedMsg}</Alert>}
            {staffNote && <Alert color="yellow" variant="light">Client-side block (does not apply to staff): {staffNote}</Alert>}

            {canAct ? (
              <Group>
                <Button variant="light" color="orange" leftSection={<IconLockOpen size={15} />} disabled={!!blockedMsg || busy}
                  onClick={() => (portal ? setConfirmFor('unlock') : unlockM.mutate())} loading={unlockM.isPending && !portal}>
                  Unlock domain
                </Button>
                <Button variant="light" color="green" leftSection={<IconLock size={15} />} loading={lockM.isPending} disabled={busy} onClick={() => lockM.mutate()}>
                  Lock domain
                </Button>
                <Button leftSection={<IconKey size={15} />} disabled={!!blockedMsg || busy} loading={codeM.isPending && !portal}
                  onClick={() => (portal ? setConfirmFor('code') : codeM.mutate())}>
                  Get transfer code
                </Button>
              </Group>
            ) : (
              <Alert color="gray" variant="light">Only administrators can unlock this domain or get its transfer code.</Alert>
            )}
            <Text size="xs" c="dimmed">Every unlock and code request is recorded and our team is notified.</Text>
          </>
        )}
      </Stack>

      <Modal opened={confirmFor !== null} onClose={closeConfirm} centered title={confirmFor === 'unlock' ? 'Unlock this domain?' : 'Get the transfer code?'}>
        <Stack gap="sm">
          <Alert color="red" variant="light" icon={<IconAlertTriangle size={16} />}>
            <List size="sm" spacing={4}>
              <List.Item>Once transferred away, we will no longer manage or host this domain, and its services with us may stop working.</List.Item>
              <List.Item>Anyone holding the transfer code can move your domain once it is unlocked. Never share it.</List.Item>
              <List.Item>Newly registered or recently changed domains can be under a mandatory transfer restriction set by the registry rules.</List.Item>
            </List>
          </Alert>
          <Text size="sm">Type <b>{domainName}</b> to confirm.</Text>
          <TextInput value={typed} onChange={(e) => setTyped(e.currentTarget.value)} placeholder={domainName} autoComplete="off" />
          <Group justify="flex-end">
            <Button variant="default" onClick={closeConfirm}>Cancel</Button>
            <Button color="red" disabled={!typedOk} loading={confirmFor === 'unlock' ? unlockM.isPending : codeM.isPending}
              onClick={() => (confirmFor === 'unlock' ? unlockM.mutate() : codeM.mutate())}>
              {confirmFor === 'unlock' ? 'Unlock domain' : 'Show transfer code'}
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={code !== null} onClose={() => setCode(null)} centered title="Transfer authorization code" closeOnClickOutside={false}>
        <Stack gap="sm">
          <Alert color="orange" variant="light" icon={<IconAlertTriangle size={16} />}>
            This code is shown only once and is not stored by us. Copy it now and keep it secret.
          </Alert>
          <Group wrap="nowrap" align="center">
            <Code fz="md" style={{ wordBreak: 'break-all', flex: 1 }}>{code}</Code>
            <CopyButton value={code ?? ''}>
              {({ copied, copy }) => (
                <Button size="xs" variant="light" color={copied ? 'green' : 'blue'} leftSection={<IconCopy size={13} />} onClick={copy}>
                  {copied ? 'Copied' : 'Copy'}
                </Button>
              )}
            </CopyButton>
          </Group>
          <Text size="xs" c="dimmed">The domain must also be unlocked before another provider can accept the transfer.</Text>
          <Button onClick={() => setCode(null)}>Close</Button>
        </Stack>
      </Modal>
    </Paper>
  );
}
