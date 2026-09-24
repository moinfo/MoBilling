import { useState } from 'react';
import { Modal, Stack, Text, Alert, Loader, Center, Table, Checkbox, Button, Group, Code, Badge } from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { useMediaQuery } from '@mantine/hooks';
import { previewNameComRegistration, registerAtNameCom } from '../api/namecom';

const errMsg = (e: any): string => e?.response?.data?.message || e?.message || 'Something went wrong';

/** Staff: shows exactly what will be bought at Name.com (real money) and requires explicit confirmation. */
export default function NameComRegisterModal({ domainId, domainName, onClose }: { domainId: string; domainName: string; onClose: () => void }) {
  const qc = useQueryClient();
  const mobile = useMediaQuery('(max-width: 48em)');
  const [ok, setOk] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { data, isLoading, error: loadErr } = useQuery({ queryKey: ['namecom-reg-preview', domainId], queryFn: () => previewNameComRegistration(domainId), retry: false, gcTime: 0, staleTime: 0 });
  const p = data?.data?.data;

  const run = useMutation({
    mutationFn: () => registerAtNameCom(domainId, p!.usd_cost!),
    onSuccess: (r) => {
      notifications.show({ color: 'green', message: r.data.message });
      qc.invalidateQueries({ queryKey: ['domains'] }); qc.invalidateQueries({ queryKey: ['domain'] }); qc.invalidateQueries({ queryKey: ['domain-stats'] });
      onClose();
    },
    onError: (e) => setError(errMsg(e)),
  });

  return (
    <Modal opened onClose={onClose} title={`Register ${domainName} at Name.com`} size="lg" fullScreen={!!mobile} zIndex={400}>
      {isLoading ? <Center py="lg"><Loader size="sm" /></Center> : loadErr ? <Alert color="red">{errMsg(loadErr)}</Alert> : p && (
        <Stack>
          <Alert color="red" variant="light" title="This spends real money">
            Clicking Register charges your Name.com account balance immediately. It cannot be undone through MoBilling.
          </Alert>
          {p.blockers.map((b) => <Alert key={b} color="orange" variant="light">{b}</Alert>)}
          {p.notes.map((b) => <Alert key={b} color="blue" variant="light">{b}</Alert>)}
          {p.price_changed && <Alert color="orange" variant="light">The live Name.com price is higher than the synced price - check it before confirming.</Alert>}
          <Table withTableBorder>
            <Table.Tbody>
              <Table.Tr><Table.Th>Domain</Table.Th><Table.Td>{p.domain}</Table.Td></Table.Tr>
              <Table.Tr><Table.Th>Client (registrant)</Table.Th><Table.Td>{p.client?.name ?? '-'}</Table.Td></Table.Tr>
              <Table.Tr><Table.Th>Years</Table.Th><Table.Td>{p.years}</Table.Td></Table.Tr>
              <Table.Tr><Table.Th>Cost at Name.com (USD)</Table.Th><Table.Td fw={700}>{p.usd_cost !== null ? `$${p.usd_cost.toFixed(2)}` : '-'} {p.usd_expected !== null && <Text span size="xs" c="dimmed">(synced price ${p.usd_expected.toFixed(2)})</Text>}</Table.Td></Table.Tr>
              <Table.Tr><Table.Th>Customer paid</Table.Th><Table.Td>{p.invoice_total !== null ? `${p.invoice_total.toLocaleString()} TZS` : '-'} {p.invoice_number && <Badge variant="light">{p.invoice_number}</Badge>}</Table.Td></Table.Tr>
              <Table.Tr><Table.Th>Availability</Table.Th><Table.Td>{p.available === null ? 'unknown' : p.available ? 'Available' : 'Not available'}</Table.Td></Table.Tr>
            </Table.Tbody>
          </Table>
          <Text size="sm" fw={600}>Contact sent to Name.com (registrant, admin, tech, billing)</Text>
          <Code block>{JSON.stringify(p.contact, null, 2)}</Code>
          {p.missing.length > 0 && <Alert color="red">Missing on the client record: {p.missing.join(', ')}. Edit the client, then reopen this window.</Alert>}
          <Checkbox checked={ok} onChange={(e) => setOk(e.currentTarget.checked)} disabled={!p.can_register}
            label={`I confirm: register ${p.domain} for ${p.years} year(s) at Name.com for about $${(p.usd_cost ?? 0).toFixed(2)}.`} />
          {error && <Alert color="red">{error}</Alert>}
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button color="red" disabled={!ok || !p.can_register || p.usd_cost === null} loading={run.isPending} onClick={() => { setError(null); run.mutate(); }}>
              Register at Name.com
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}
