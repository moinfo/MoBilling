import { useState } from 'react';
import { Modal, Stack, Text, Alert, TextInput, Group, Button } from '@mantine/core';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { linodePower, getLinodeServerStatus, LinodeResource, PowerAction } from '../api/linode';

export const BUSY_STATUSES = ['booting', 'rebooting', 'shutting_down', 'provisioning', 'migrating', 'rebuilding', 'cloning', 'restoring', 'resizing'];
const SETTLED = ['running', 'offline'];

/** Poll one server every 5s (max ~2 min) until it is running/offline again, refreshing the servers list as it goes. */
export function pollServerStatus(id: string, onTick: () => void) {
  let n = 0;
  const t = setInterval(async () => {
    n++;
    try {
      const r = await getLinodeServerStatus(id);
      onTick();
      if (SETTLED.includes(r.data.data.status)) clearInterval(t);
    } catch { /* keep trying until the limit */ }
    if (n >= 24) clearInterval(t);
  }, 5000);
}

const errMsg = (e: any): string => e?.response?.data?.message || e?.message || 'Something went wrong';

const COPY: Record<PowerAction, { title: string; color: string; warn: string | null }> = {
  reboot: { title: 'Reboot server', color: 'orange', warn: 'Short downtime: the server restarts and is unreachable for a minute or two.' },
  shutdown: { title: 'Shut down server', color: 'red', warn: 'All websites and services on this server will go offline until it is started again.' },
  boot: { title: 'Boot server', color: 'green', warn: null },
};

export default function LinodePowerModal({ server, action, onClose, onDone }: {
  server: LinodeResource; action: PowerAction; onClose: () => void; onDone?: () => void;
}) {
  const qc = useQueryClient();
  const [typed, setTyped] = useState('');
  const c = COPY[action];
  const needsLabel = action !== 'boot';
  const run = useMutation({
    mutationFn: () => linodePower(server.id, action === 'boot' ? { action, confirm: true } : { action, confirm_label: typed }),
    onSuccess: (r) => {
      notifications.show({ color: 'green', message: r.data.message + ' Watching status...' });
      qc.invalidateQueries({ queryKey: ['linode-servers'] });
      pollServerStatus(server.id, () => qc.invalidateQueries({ queryKey: ['linode-servers'] }));
      onDone?.();
      onClose();
    },
    onError: (e) => notifications.show({ color: 'red', title: c.title, message: errMsg(e), autoClose: 10000 }),
  });
  return (
    <Modal opened onClose={onClose} title={c.title} centered>
      <Stack>
        <Text size="sm">Server: <b>{server.label}</b> ({server.ipv4.join(', ') || 'no IP'})</Text>
        <Text size="sm">Client: <b>{server.client_name ?? 'not mapped'}</b></Text>
        {c.warn && <Alert color={c.color} variant="light">{c.warn}</Alert>}
        {needsLabel && (
          <TextInput label={`Type the server name (${server.label}) to confirm`} value={typed} onChange={(e) => setTyped(e.currentTarget.value)} data-autofocus />
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button color={c.color} loading={run.isPending} disabled={needsLabel && typed !== server.label} onClick={() => run.mutate()}>{c.title}</Button>
        </Group>
      </Stack>
    </Modal>
  );
}
