import { useState } from 'react';
import {
  Title, Table, Badge, ActionIcon, Modal, Stack, TextInput, Textarea,
  NumberInput, Switch, Button, Group, Text, Loader, Center, Paper, Alert,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconEdit, IconInfoCircle } from '@tabler/icons-react';
import { getLicensePlans, updateLicensePlan, LicensePlan, LicensePlanFormData } from '../../api/admin';
import { formatCurrency } from '../../utils/formatCurrency';

export default function LicensePlans() {
  const queryClient = useQueryClient();
  const [editPlan, setEditPlan] = useState<LicensePlan | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-license-plans'],
    queryFn: getLicensePlans,
  });

  const plans: LicensePlan[] = data?.data?.data || [];

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <div>
          <Title order={2}>License Plans</Title>
          <Text c="dimmed">Pricing for self-hosted installs — a customer running MoBilling on their own server. Separate from Subscription Plans, which price MoBilling SaaS itself.</Text>
        </div>
      </Group>

      <Alert icon={<IconInfoCircle size={16} />} color="blue" mb="md">
        These three rows are fixed (same packages as Licenses/signup) — edit prices per billing period. Leave a period blank if you don't offer it for that package.
      </Alert>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Paper withBorder>
          <Table.ScrollContainer minWidth={800}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Package</Table.Th>
                  <Table.Th>Monthly</Table.Th>
                  <Table.Th>Quarterly</Table.Th>
                  <Table.Th>Semi-Annual</Table.Th>
                  <Table.Th>Annual</Table.Th>
                  <Table.Th>Perpetual</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th w={80}>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {plans.map((plan) => (
                  <Table.Tr key={plan.id}>
                    <Table.Td>
                      <Text fw={500}>{plan.name}</Text>
                      <Text size="xs" c="dimmed">{plan.description}</Text>
                    </Table.Td>
                    <Table.Td>{plan.monthly_price ? formatCurrency(plan.monthly_price) : '—'}</Table.Td>
                    <Table.Td>{plan.quarterly_price ? formatCurrency(plan.quarterly_price) : '—'}</Table.Td>
                    <Table.Td>{plan.semi_annual_price ? formatCurrency(plan.semi_annual_price) : '—'}</Table.Td>
                    <Table.Td>{plan.annual_price ? formatCurrency(plan.annual_price) : '—'}</Table.Td>
                    <Table.Td>{plan.perpetual_price ? formatCurrency(plan.perpetual_price) : '—'}</Table.Td>
                    <Table.Td>
                      <Badge color={plan.is_active ? 'green' : 'gray'} variant="light">
                        {plan.is_active ? 'Active' : 'Inactive'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <ActionIcon variant="subtle" onClick={() => setEditPlan(plan)}>
                        <IconEdit size={16} />
                      </ActionIcon>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      <Modal opened={!!editPlan} onClose={() => setEditPlan(null)} title={`Edit — ${editPlan?.name}`}>
        {editPlan && (
          <PlanForm existing={editPlan} onSaved={() => { queryClient.invalidateQueries({ queryKey: ['admin-license-plans'] }); setEditPlan(null); }} />
        )}
      </Modal>
    </>
  );
}

function PlanForm({ existing, onSaved }: { existing: LicensePlan; onSaved: () => void }) {
  const form = useForm<LicensePlanFormData>({
    initialValues: {
      name: existing.name,
      description: existing.description ?? '',
      monthly_price: existing.monthly_price ? Number(existing.monthly_price) : null,
      quarterly_price: existing.quarterly_price ? Number(existing.quarterly_price) : null,
      semi_annual_price: existing.semi_annual_price ? Number(existing.semi_annual_price) : null,
      annual_price: existing.annual_price ? Number(existing.annual_price) : null,
      perpetual_price: existing.perpetual_price ? Number(existing.perpetual_price) : null,
      is_active: existing.is_active,
    },
  });

  const mutation = useMutation({
    mutationFn: (values: LicensePlanFormData) => updateLicensePlan(existing.id, values),
    onSuccess: () => {
      notifications.show({ title: 'Success', message: 'Plan updated', color: 'green' });
      onSaved();
    },
    onError: (err: any) => notifications.show({
      title: 'Error', message: err.response?.data?.message || 'Failed to update plan', color: 'red',
    }),
  });

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <TextInput label="Name" required {...form.getInputProps('name')} />
        <Textarea label="Description" minRows={2} {...form.getInputProps('description')} />
        <NumberInput label="Monthly Price (TZS)" min={0} placeholder="Not offered" {...form.getInputProps('monthly_price')} />
        <NumberInput label="Quarterly Price (TZS)" min={0} placeholder="Not offered" {...form.getInputProps('quarterly_price')} />
        <NumberInput label="Semi-Annual Price (TZS)" min={0} placeholder="Not offered" {...form.getInputProps('semi_annual_price')} />
        <NumberInput label="Annual Price (TZS)" min={0} placeholder="Not offered" {...form.getInputProps('annual_price')} />
        <NumberInput label="Perpetual Price (TZS)" min={0} placeholder="Not offered" {...form.getInputProps('perpetual_price')} />
        <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>Save</Button>
        </Group>
      </Stack>
    </form>
  );
}
