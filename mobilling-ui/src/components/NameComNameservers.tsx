import { useState } from 'react';
import { Stack, Group, Text, TextInput, Button, Alert, Loader, Code, Title, Paper } from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconServer } from '@tabler/icons-react';
import { NAMECOM_LINODE_NAMESERVERS } from '../api/namecom';

interface NsData { nameservers: string[]; original_nameservers?: string[]; editable?: boolean }

/**
 * Nameserver editor for externally managed domains (staff drawer + client portal).
 * Live read, 2-13 hostnames, presets, confirmation before saving.
 */
export default function NameComNameservers({ queryKey, fetcher, saver, canEdit, portal, invalidate = [] }: {
  queryKey: unknown[];
  fetcher: () => Promise<{ data: { data: NsData } }>;
  saver: (ns: string[]) => Promise<{ data: { message: string } }>;
  canEdit: boolean;
  portal?: boolean;
  invalidate?: unknown[][];
}) {
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [values, setValues] = useState<string[]>([]);

  const { data, isLoading, isError, error } = useQuery({ queryKey, queryFn: fetcher, retry: false });
  const ns = data?.data?.data;
  const loadErr = (error as any)?.response?.data?.message as string | undefined;

  const save = useMutation({
    mutationFn: (list: string[]) => saver(list),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey });
      invalidate.forEach((k) => qc.invalidateQueries({ queryKey: k }));
      notifications.show({ title: 'Nameservers updated', message: res.data.message, color: 'green', autoClose: 9000 });
      setEditing(false);
    },
    onError: (e: any) => notifications.show({
      title: 'Update failed',
      message: e?.response?.data?.message ?? (Object.values(e?.response?.data?.errors ?? {}).flat().join(' ') || 'Please check the hostnames and try again.'),
      color: 'red',
    }),
  });

  const startEdit = () => {
    const cur = ns?.nameservers ?? [];
    setValues(cur.length >= 2 ? [...cur] : [...cur, ...Array(2 - cur.length).fill('')]);
    setEditing(true);
  };

  const filled = values.map((v) => v.trim().toLowerCase()).filter(Boolean);
  const hostOk = filled.every((h) => /^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/.test(h));
  const canSave = filled.length >= 2 && filled.length <= 13 && new Set(filled).size === filled.length && hostOk;
  const original = ns?.original_nameservers ?? [];

  const confirm = () => modals.openConfirmModal({
    title: 'Change nameservers?',
    centered: true,
    children: (
      <Stack gap={6}>
        <Text size="sm">Your website and email will follow the new nameservers. Wrong values take them offline.</Text>
        {filled.map((h) => <Code key={h}>{h}</Code>)}
      </Stack>
    ),
    labels: { confirm: 'Yes, change nameservers', cancel: 'Cancel' },
    confirmProps: { color: 'green' },
    onConfirm: () => save.mutate(filled),
  });

  const body = (
    <>
      {isLoading ? (
        <Group gap="xs"><Loader size="xs" /><Text size="sm" c="dimmed">{portal ? 'Loading nameservers...' : 'Fetching live from Name.com...'}</Text></Group>
      ) : isError || !ns ? (
        <Alert color="orange" variant="light">{loadErr ?? 'Could not read the nameservers right now - please try again shortly.'}</Alert>
      ) : !editing ? (
        <Stack gap={6}>
          {ns.nameservers.length === 0 && <Text size="sm" c="dimmed">No nameservers are set for this domain.</Text>}
          {ns.nameservers.map((n, i) => (
            <Group key={n} gap="xs" wrap="nowrap">
              <Text size="sm" c="dimmed" w={40}>NS{i + 1}</Text>
              <Code fz="sm" style={{ wordBreak: 'break-all' }}>{n}</Code>
            </Group>
          ))}
          {portal && !canEdit && <Text size="xs" c="dimmed" mt={4}>Only portal administrators can change nameservers.</Text>}
        </Stack>
      ) : (
        <Stack gap="xs">
          <Group gap="xs">
            <Button size="compact-xs" variant="light" onClick={() => setValues([...NAMECOM_LINODE_NAMESERVERS])}>Use Linode nameservers</Button>
            {original.length >= 2 && (
              <Button size="compact-xs" variant="light" color="gray" onClick={() => setValues([...original])}>Use default (original)</Button>
            )}
          </Group>
          {values.map((v, i) => (
            <TextInput key={i} size="sm" label={`NS${i + 1}`} placeholder={i < 2 ? 'required - e.g. ns1.example.com' : 'optional'}
              value={v} onChange={(e) => setValues(values.map((x, j) => (j === i ? e.currentTarget.value.toLowerCase() : x)))} />
          ))}
          {values.length < 13 && (
            <Button size="compact-xs" variant="subtle" w="fit-content" onClick={() => setValues([...values, ''])}>+ add another</Button>
          )}
          <Alert color="orange" variant="light" p="xs">
            Use 2 to 13 nameservers that already host this domain's DNS. Changes can take a few hours to propagate.
            Up to 5 changes per domain per day.
          </Alert>
          <Group justify="flex-end" mt="xs">
            <Button size="xs" variant="default" onClick={() => setEditing(false)}>Cancel</Button>
            <Button size="xs" color="green" disabled={!canSave} loading={save.isPending} onClick={confirm}>Save nameservers</Button>
          </Group>
        </Stack>
      )}
    </>
  );

  const header = (
    <Group justify="space-between" mb="md" wrap="wrap">
      {portal
        ? <Title order={4}>Nameservers</Title>
        : <Group gap="xs"><IconServer size={18} /><Title order={5}>Nameservers (DNS) - Name.com</Title></Group>}
      {!editing && canEdit && ns?.editable !== false && !isError && !isLoading && (
        <Button size="xs" variant="light" onClick={startEdit}>Change nameservers</Button>
      )}
    </Group>
  );

  return portal
    ? <Stack gap="md">{header}<Text size="sm" c="dimmed">Nameservers control where your domain points - your website and email follow them. Only change these if you know the nameservers of your hosting provider.</Text>{body}</Stack>
    : <Paper withBorder radius="md" p="lg">{header}{body}</Paper>;
}
