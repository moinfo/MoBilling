import { useState } from 'react';
import {
  Title, Table, Badge, ActionIcon, Modal, Stack, TextInput, NumberInput,
  Switch, Button, Group, Text, Loader, Center, Paper, Textarea, TagsInput,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { notifications } from '@mantine/notifications';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { IconPlus, IconEdit, IconTrash } from '@tabler/icons-react';
import {
  getAdminSubscriptionPlans, createSubscriptionPlan, updateSubscriptionPlan,
  deleteSubscriptionPlan, SubscriptionPlanAdmin, SubscriptionPlanFormData,
} from '../../api/admin';

export default function SubscriptionPlans() {
  const queryClient = useQueryClient();
  const [editPlan, setEditPlan] = useState<SubscriptionPlanAdmin | null>(null);
  const [createOpen, setCreateOpen] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['admin-subscription-plans'],
    queryFn: getAdminSubscriptionPlans,
  });

  const plans: SubscriptionPlanAdmin[] = data?.data?.data || [];

  const deleteMut = useMutation({
    mutationFn: deleteSubscriptionPlan,
    onSuccess: () => {
      notifications.show({ title: 'Deleted', message: 'Plan deleted', color: 'green' });
      queryClient.invalidateQueries({ queryKey: ['admin-subscription-plans'] });
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to delete',
        color: 'red',
      });
    },
  });

  return (
    <>
      <Group justify="space-between" mb="md" wrap="wrap">
        <div>
          <Title order={2}>Subscription Plans</Title>
          <Text c="dimmed">Manage tenant subscription plans and pricing.</Text>
        </div>
        <Button leftSection={<IconPlus size={16} />} onClick={() => setCreateOpen(true)}>
          Add Plan
        </Button>
      </Group>

      {isLoading ? (
        <Center py="xl"><Loader /></Center>
      ) : (
        <Paper withBorder>
          <Table.ScrollContainer minWidth={750}>
            <Table striped highlightOnHover>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Name</Table.Th>
                  <Table.Th>Slug</Table.Th>
                  <Table.Th>Price (TZS)</Table.Th>
                  <Table.Th>Cycle (days)</Table.Th>
                  <Table.Th>Features</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Order</Table.Th>
                  <Table.Th w={100}>Actions</Table.Th>
                </Table.Tr>
              </Table.Thead>
            <Table.Tbody>
              {plans.map((plan) => (
                <Table.Tr key={plan.id}>
                  <Table.Td fw={500}>{plan.name}</Table.Td>
                  <Table.Td><Text size="sm" c="dimmed">{plan.slug}</Text></Table.Td>
                  <Table.Td>{Number(plan.price).toLocaleString()}</Table.Td>
                  <Table.Td>{plan.billing_cycle_days}</Table.Td>
                  <Table.Td>
                    {plan.features?.length
                      ? <Text size="sm" lineClamp={1}>{plan.features.join(', ')}</Text>
                      : <Text size="sm" c="dimmed">—</Text>}
                  </Table.Td>
                  <Table.Td>
                    <Badge color={plan.is_active ? 'green' : 'gray'} variant="light">
                      {plan.is_active ? 'Active' : 'Inactive'}
                    </Badge>
                  </Table.Td>
                  <Table.Td>{plan.sort_order}</Table.Td>
                  <Table.Td>
                    <Group gap={4}>
                      <ActionIcon variant="subtle" onClick={() => setEditPlan(plan)}>
                        <IconEdit size={16} />
                      </ActionIcon>
                      <ActionIcon
                        variant="subtle"
                        color="red"
                        loading={deleteMut.isPending}
                        onClick={() => {
                          if (confirm(`Delete "${plan.name}"?`)) deleteMut.mutate(plan.id);
                        }}
                      >
                        <IconTrash size={16} />
                      </ActionIcon>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
              {plans.length === 0 && (
                <Table.Tr>
                  <Table.Td colSpan={8}>
                    <Text ta="center" c="dimmed" py="md">No subscription plans yet</Text>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        </Paper>
      )}

      <Modal opened={createOpen} onClose={() => setCreateOpen(false)} title="Add Subscription Plan" size="lg">
        <PlanForm
          onSaved={() => {
            queryClient.invalidateQueries({ queryKey: ['admin-subscription-plans'] });
            setCreateOpen(false);
          }}
        />
      </Modal>

      <Modal opened={!!editPlan} onClose={() => setEditPlan(null)} title={`Edit — ${editPlan?.name}`} size="lg">
        {editPlan && (
          <PlanForm
            existing={editPlan}
            onSaved={() => {
              queryClient.invalidateQueries({ queryKey: ['admin-subscription-plans'] });
              setEditPlan(null);
            }}
          />
        )}
      </Modal>
    </>
  );
}

function PlanForm({ existing, onSaved }: { existing?: SubscriptionPlanAdmin; onSaved: () => void }) {
  const form = useForm<SubscriptionPlanFormData>({
    initialValues: {
      name: existing?.name ?? '',
      slug: existing?.slug ?? '',
      description: existing?.description ?? '',
      price: existing ? Number(existing.price) : '',
      billing_cycle_days: existing?.billing_cycle_days ?? 30,
      features: existing?.features ?? [],
      is_active: existing?.is_active ?? true,
      sort_order: existing?.sort_order ?? 0,
    },
  });

  const mutation = useMutation({
    mutationFn: (values: SubscriptionPlanFormData) =>
      existing ? updateSubscriptionPlan(existing.id, values) : createSubscriptionPlan(values),
    onSuccess: () => {
      notifications.show({
        title: 'Success',
        message: existing ? 'Plan updated' : 'Plan created',
        color: 'green',
      });
      onSaved();
    },
    onError: (err: any) => {
      notifications.show({
        title: 'Error',
        message: err.response?.data?.message || 'Failed to save plan',
        color: 'red',
      });
    },
  });

  // Auto-generate slug from name
  const handleNameChange = (name: string) => {
    form.setFieldValue('name', name);
    if (!existing) {
      form.setFieldValue('slug', name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, ''));
    }
  };

  return (
    <form onSubmit={form.onSubmit((values) => mutation.mutate(values))}>
      <Stack>
        <TextInput
          label="Plan Name"
          placeholder="e.g. Basic Monthly"
          required
          value={form.values.name}
          onChange={(e) => handleNameChange(e.currentTarget.value)}
          error={form.errors.name}
        />
        <TextInput label="Slug" placeholder="basic-monthly" required {...form.getInputProps('slug')} />
        <Textarea label="Description" placeholder="What's included in this plan" {...form.getInputProps('description')} />
        <NumberInput label="Price (TZS)" placeholder="5000" min={0} decimalScale={2} required {...form.getInputProps('price')} />
        <NumberInput label="Billing Cycle (days)" placeholder="30" min={1} required {...form.getInputProps('billing_cycle_days')} />
        <TagsInput
          label="Features"
          placeholder="Press Enter to add a feature"
          value={form.values.features}
          onChange={(val) => form.setFieldValue('features', val)}
        />
        <NumberInput label="Sort Order" min={0} {...form.getInputProps('sort_order')} />
        <Switch label="Active" {...form.getInputProps('is_active', { type: 'checkbox' })} />
        <Group justify="flex-end">
          <Button type="submit" loading={mutation.isPending}>
            {existing ? 'Update' : 'Create'}
          </Button>
        </Group>
      </Stack>
    </form>
  );
}
