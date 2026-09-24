import { useState } from 'react';
import { Modal, Stack, Text, Alert, TextInput, Group, Button, Badge, Divider, Textarea, Loader } from '@mantine/core';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { IconRefresh, IconWorldWww, IconLifebuoy } from '@tabler/icons-react';
import { getPortalLinodeServer, portalLinodeReboot, portalLinodeRequestDomain, portalLinodeSupportTicket } from '../../api/portal';

const errMsg = (e: any): string =>
  e?.response?.data?.message || (e?.response?.data?.errors ? Object.values(e.response.data.errors).flat().join(' ') : null) || e?.message || 'Something went wrong';

const reqColor: Record<string, string> = { pending: 'yellow', approved: 'green', rejected: 'red' };
const reqLabel: Record<string, string> = { pending: 'Inasubiri', approved: 'Imekubaliwa', rejected: 'Imekataliwa' };

/** Buttons + modal for one Linode server on the client's subscription card. Reboot only - never shutdown/boot/delete. */
export default function PortalLinodeServer({ server, isAdmin }: { server: { id: string; name: string; status?: string | null }; isAdmin: boolean }) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [rebootOpen, setRebootOpen] = useState(false);
  const [confirm, setConfirm] = useState('');
  const [domain, setDomain] = useState('');
  const [ticketOpen, setTicketOpen] = useState(false);
  const [ticketMsg, setTicketMsg] = useState('');
  const key = ['portal-linode', server.id];
  const { data, isLoading } = useQuery({ queryKey: key, queryFn: () => getPortalLinodeServer(server.id), enabled: open });
  const info = data?.data?.data;

  const reboot = useMutation({
    mutationFn: () => portalLinodeReboot(server.id, confirm),
    onSuccess: (r) => {
      notifications.show({ color: 'green', message: r.data.message });
      setRebootOpen(false); setConfirm('');
      qc.invalidateQueries({ queryKey: ['portal-subscriptions'] }); qc.invalidateQueries({ queryKey: key });
    },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const request = useMutation({
    mutationFn: () => portalLinodeRequestDomain(server.id, domain.trim()),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); setDomain(''); qc.invalidateQueries({ queryKey: key }); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });
  const ticket = useMutation({
    mutationFn: () => portalLinodeSupportTicket(server.id, ticketMsg.trim() || undefined),
    onSuccess: (r) => { notifications.show({ color: 'green', message: r.data.message }); setTicketOpen(false); setTicketMsg(''); },
    onError: (e) => notifications.show({ color: 'red', message: errMsg(e) }),
  });

  const busy = ['booting', 'rebooting', 'shutting_down', 'provisioning', 'migrating', 'rebuilding'].includes(String(info?.server.status ?? server.status));

  return (
    <>
      <Button variant="light" size="compact-sm" leftSection={<IconWorldWww size={14} />} onClick={() => setOpen(true)}>Server</Button>
      <Modal opened={open} onClose={() => setOpen(false)} title={`Server ${server.name}`} size="lg">
        {isLoading || !info ? <Loader size="sm" /> : (
          <Stack>
            <Text size="sm" c="dimmed">
              {info.server.ip ?? '-'} · {info.server.region ?? '-'} · <Badge size="sm" variant="light">{info.server.status ?? '-'}</Badge>
            </Text>
            <Group>
              {isAdmin && (
                <Button color="orange" variant="light" leftSection={<IconRefresh size={16} />} disabled={busy || info.server.status !== 'running'}
                  onClick={() => { setConfirm(''); setRebootOpen(true); }}>Washa upya server</Button>
              )}
              <Button variant="light" leftSection={<IconLifebuoy size={16} />} onClick={() => setTicketOpen(true)}>Omba msaada wa server</Button>
            </Group>

            <Divider label="Domains kwenye server hii" labelPosition="left" />
            {info.domains.length === 0
              ? <Text size="sm" c="dimmed">Hakuna domain iliyounganishwa bado.</Text>
              : <Group gap="xs">{info.domains.map((d) => <Badge key={d.name} variant="outline">{d.name}</Badge>)}</Group>}

            {isAdmin && (
              <>
                <Divider label="Omba kuongeza domain" labelPosition="left" />
                <Group align="flex-end" wrap="nowrap">
                  <TextInput style={{ flex: 1 }} placeholder="mfano: biashara.co.tz" value={domain} onChange={(e) => setDomain(e.currentTarget.value)} />
                  <Button loading={request.isPending} disabled={!domain.trim()} onClick={() => request.mutate()}>Tuma ombi</Button>
                </Group>
                <Text size="xs" c="dimmed">Tutaiongeza kwenye server yako na kukutaarifu. Baada ya hapo weka nameservers za Linode kwa msajili wa domain.</Text>
              </>
            )}
            {info.requests.length > 0 && (
              <Stack gap={4}>
                {info.requests.map((r) => (
                  <Group key={r.id} justify="space-between" wrap="nowrap">
                    <Text size="sm">{r.domain}{r.note ? <Text span size="xs" c="dimmed"> · {r.note}</Text> : null}</Text>
                    <Badge color={reqColor[r.status]} variant="light" size="sm">{reqLabel[r.status]}</Badge>
                  </Group>
                ))}
              </Stack>
            )}
          </Stack>
        )}
      </Modal>

      <Modal opened={rebootOpen} onClose={() => setRebootOpen(false)} title="Washa upya server" zIndex={400}>
        <Stack>
          <Alert color="orange">Server itazimwa na kuwashwa upya; tovuti zitakuwa hazipatikani kwa dakika 1-2.</Alert>
          <TextInput label={`Andika jina la server (${server.name}) kuthibitisha`} value={confirm} onChange={(e) => setConfirm(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setRebootOpen(false)}>Ghairi</Button>
            <Button color="orange" loading={reboot.isPending} disabled={confirm !== server.name} onClick={() => reboot.mutate()}>Washa upya</Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={ticketOpen} onClose={() => setTicketOpen(false)} title="Omba msaada wa server" zIndex={400}>
        <Stack>
          <Text size="sm" c="dimmed">Tutafungua tiketi yenye taarifa za server ({server.name}). Unaweza kuongeza maelezo.</Text>
          <Textarea minRows={3} maxLength={5000} placeholder="Elezea tatizo (si lazima)" value={ticketMsg} onChange={(e) => setTicketMsg(e.currentTarget.value)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setTicketOpen(false)}>Ghairi</Button>
            <Button loading={ticket.isPending} onClick={() => ticket.mutate()}>Tuma</Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}
