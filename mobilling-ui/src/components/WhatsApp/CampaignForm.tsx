import { useEffect } from 'react';
import { useForm } from '@mantine/form';
import { TextInput, Textarea, NumberInput, Stack, Button, Group, Modal } from '@mantine/core';
import { DatePickerInput } from '@mantine/dates';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import { WhatsappCampaign, createCampaign, updateCampaign } from '../../api/whatsappCampaigns';

interface Props {
  opened: boolean;
  onClose: () => void;
  campaign?: WhatsappCampaign | null;
}

export default function CampaignForm({ opened, onClose, campaign }: Props) {
  const qc = useQueryClient();

  const form = useForm({
    initialValues: {
      name: '',
      start_date: null as Date | null,
      end_date: null as Date | null,
      budget: 0,
      notes: '',
    },
    validate: {
      name: (v) => v.trim() ? null : 'Name is required',
      start_date: (v) => v ? null : 'Start date is required',
      budget: (v) => v >= 0 ? null : 'Budget must be 0 or more',
    },
  });

  useEffect(() => {
    if (campaign) {
      form.setValues({
        name: campaign.name,
        start_date: new Date(campaign.start_date),
        end_date: campaign.end_date ? new Date(campaign.end_date) : null,
        budget: campaign.budget,
        notes: campaign.notes ?? '',
      });
    } else {
      form.reset();
    }
  }, [campaign, opened]);

  const toDateStr = (val: any): string | null => {
    if (!val) return null;
    const d = val instanceof Date ? val : new Date(val);
    return isNaN(d.getTime()) ? null : d.toISOString().split('T')[0];
  };

  const mutation = useMutation({
    mutationFn: (values: any) => {
      const payload = {
        ...values,
        start_date: toDateStr(values.start_date),
        end_date: toDateStr(values.end_date),
        notes: values.notes || null,
        budget: Number(values.budget) || 0,
      };
      return campaign ? updateCampaign(campaign.id, payload) : createCampaign(payload);
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['whatsapp-campaigns'] });
      notifications.show({ message: campaign ? 'Campaign updated' : 'Campaign created', color: 'green' });
      onClose();
    },
    onError: () => {
      notifications.show({ message: 'Failed to save campaign', color: 'red' });
    },
  });

  return (
    <Modal opened={opened} onClose={onClose} title={campaign ? 'Edit Campaign' : 'New Ad Campaign'} size="sm">
      <form onSubmit={form.onSubmit((v) => mutation.mutate(v))}>
        <Stack gap="sm">
          <TextInput label="Campaign Name" required placeholder="e.g. April Promo 2026" {...form.getInputProps('name')} />

          <Group grow>
            <DatePickerInput label="Start Date" required {...form.getInputProps('start_date')} />
            <DatePickerInput label="End Date" clearable {...form.getInputProps('end_date')} />
          </Group>

          <NumberInput
            label="Budget Spent"
            required
            min={0}
            prefix="TZS "
            thousandSeparator=","
            {...form.getInputProps('budget')}
          />

          <Textarea label="Notes" rows={2} placeholder="Target audience, objective..." {...form.getInputProps('notes')} />

          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose}>Cancel</Button>
            <Button type="submit" loading={mutation.isPending} color="green">
              {campaign ? 'Save Changes' : 'Create Campaign'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
}
