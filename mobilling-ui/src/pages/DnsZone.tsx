import { useMemo, useState } from 'react';
import { Stack, Paper, Title, Text, Group, Select, Loader } from '@mantine/core';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { IconWorldWww } from '@tabler/icons-react';
import { discoverHostingAccounts, getDnsZone, addDnsRecord, DiscoveredAccount } from '../api/hosting';
import { usePermissions } from '../hooks/usePermissions';
import WhmDnsSection, { WhmAddDnsRecordInput } from '../components/Hosting/WhmDnsSection';

/**
 * A hosting account's DNS zone (WHM's parse_dns_zone/addzonerecord, via
 * WhmDnsSection — see that component for the add-only rationale).
 */
export default function DnsZone() {
  const { can } = usePermissions();
  const canAdd = can('hosting.change_package');
  const qc = useQueryClient();
  const [selected, setSelected] = useState<string | null>(null);

  const { data: accountsData, isLoading: accountsLoading } = useQuery({
    queryKey: ['discover-hosting', undefined, 'all'],
    queryFn: () => discoverHostingAccounts({}),
    staleTime: 60_000,
  });
  const accounts: DiscoveredAccount[] = accountsData?.data?.data ?? [];

  const options = useMemo(() => accounts
    .filter((a) => a.domain)
    .slice()
    .sort((a, b) => (a.domain ?? '').localeCompare(b.domain ?? ''))
    .map((a) => ({
      value: `${a.server_id}|${a.domain}`,
      label: `${a.domain}${a.client ? ` — ${a.client.name}` : ''}`,
    })), [accounts]);

  const [serverId, domain] = selected ? selected.split('|') : [null, null];

  const { data: zoneData, isLoading: zoneLoading, isError } = useQuery({
    queryKey: ['dns-zone', serverId, domain],
    queryFn: () => getDnsZone({ server_id: serverId!, domain: domain! }),
    enabled: !!serverId && !!domain,
  });
  const records = zoneData?.data?.data ?? [];

  const handleAdd = async (v: WhmAddDnsRecordInput) => {
    await addDnsRecord({ server_id: serverId!, domain: domain!, ...v });
    qc.invalidateQueries({ queryKey: ['dns-zone', serverId, domain] });
  };

  return (
    <Stack gap="md">
      <Title order={3}>
        <Group gap="xs"><IconWorldWww size={22} /> DNS Zone</Group>
      </Title>

      <Paper withBorder p="sm" radius="sm">
        <Select
          label="Domain" placeholder="Search domain or client…" searchable clearable
          data={options} value={selected} onChange={setSelected}
          disabled={accountsLoading}
          rightSection={accountsLoading ? <Loader size="xs" /> : undefined}
          maw={500}
        />
      </Paper>

      {selected && domain ? (
        <WhmDnsSection
          domain={domain}
          records={records}
          isLoading={zoneLoading}
          isError={isError}
          canAdd={canAdd}
          onAddRecord={handleAdd}
        />
      ) : (
        <Text size="sm" c="dimmed">Pick a domain to see its DNS zone straight from WHM.</Text>
      )}
    </Stack>
  );
}
