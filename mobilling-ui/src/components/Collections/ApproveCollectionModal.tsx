import { useState } from 'react';
import { Modal, Stack, Text, Textarea, Group, Button } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { approveForCollection } from '../../api/documents';

interface Props {
  opened: boolean;
  onClose: () => void;
  documentId: string;
  documentNumber: string;
  onApproved: () => void;
}

/** Admin review: approve an unpaid invoice as legitimately collectible (with optional notes). */
export default function ApproveCollectionModal({ opened, onClose, documentId, documentNumber, onApproved }: Props) {
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  const submit = async () => {
    setSaving(true);
    try {
      const res = await approveForCollection(documentId, notes.trim());
      notifications.show({ title: 'Approved', message: res.data.message, color: 'green' });
      setNotes('');
      onApproved();
      onClose();
    } catch (err: any) {
      notifications.show({
        title: 'Cannot approve',
        message: err?.response?.data?.message ?? 'Failed to approve invoice for collection.',
        color: 'red',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal opened={opened} onClose={onClose} title={`Approve ${documentNumber} for collection`} size="md" centered>
      <Stack>
        <Text size="sm" c="dimmed">
          Confirm this debt is genuine and collectible. Once approved it can be assigned to staff for follow-up.
          (Thibitisha deni hili ni halali kabla ya kumpa mfanyakazi.)
        </Text>
        <Textarea label="Review notes (optional)" minRows={3} maxLength={2000}
          value={notes} onChange={(e) => setNotes(e.currentTarget.value)} />
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>Cancel</Button>
          <Button color="green" onClick={submit} loading={saving}>Approve for Collection</Button>
        </Group>
      </Stack>
    </Modal>
  );
}
