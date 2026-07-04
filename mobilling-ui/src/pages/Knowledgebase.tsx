import { useState } from 'react';
import {
  Title, Stack, Group, Table, Badge, Text, Paper, Button, ActionIcon, Modal,
  TextInput, Textarea, Switch, Loader, Center, Tooltip, Select, NumberInput, Tabs,
} from '@mantine/core';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { notifications } from '@mantine/notifications';
import {
  IconBook, IconPlus, IconEdit, IconTrash, IconEye, IconEyeOff, IconFolder, IconFileText,
} from '@tabler/icons-react';
import {
  getKbCategories, createKbCategory, updateKbCategory, deleteKbCategory, KbCategoryRow,
  getKbArticles, createKbArticle, updateKbArticle, deleteKbArticle, KbArticleRow,
} from '../api/knowledgebase';

export default function Knowledgebase() {
  const qc = useQueryClient();

  // ── Category state ─────────────────────────────────────────────────────
  const [catModalOpen, setCatModalOpen] = useState(false);
  const [editingCat, setEditingCat] = useState<KbCategoryRow | null>(null);
  const [catName, setCatName] = useState('');
  const [catDesc, setCatDesc] = useState('');
  const [catSort, setCatSort] = useState<number | string>(0);
  const [catActive, setCatActive] = useState(true);

  // ── Article state ──────────────────────────────────────────────────────
  const [artModalOpen, setArtModalOpen] = useState(false);
  const [editingArt, setEditingArt] = useState<KbArticleRow | null>(null);
  const [artTitle, setArtTitle] = useState('');
  const [artBody, setArtBody] = useState('');
  const [artCategory, setArtCategory] = useState<string | null>(null);
  const [artSort, setArtSort] = useState<number | string>(0);
  const [artPublish, setArtPublish] = useState(true);

  const { data: catData, isLoading: catLoading } = useQuery({ queryKey: ['kb-categories'], queryFn: getKbCategories });
  const { data: artData, isLoading: artLoading } = useQuery({ queryKey: ['kb-articles'], queryFn: () => getKbArticles() });
  const categories: KbCategoryRow[] = catData?.data?.data ?? [];
  const articles: KbArticleRow[] = artData?.data?.data ?? [];

  const invalidateCats = () => qc.invalidateQueries({ queryKey: ['kb-categories'] });
  const invalidateArts = () => qc.invalidateQueries({ queryKey: ['kb-articles'] });

  // ── Category mutations ─────────────────────────────────────────────────
  const saveCat = useMutation({
    mutationFn: () => {
      const payload = { name: catName.trim(), description: catDesc.trim() || null, sort_order: Number(catSort) || 0, is_active: catActive };
      return editingCat ? updateKbCategory(editingCat.id, payload) : createKbCategory(payload);
    },
    onSuccess: () => {
      invalidateCats();
      notifications.show({ message: editingCat ? 'Category updated.' : 'Category created.', color: 'green' });
      setCatModalOpen(false);
    },
    onError: () => notifications.show({ message: 'Save failed.', color: 'red' }),
  });
  const deleteCat = useMutation({
    mutationFn: deleteKbCategory,
    onSuccess: () => { invalidateCats(); invalidateArts(); notifications.show({ message: 'Category deleted.', color: 'gray' }); },
  });

  // ── Article mutations ──────────────────────────────────────────────────
  const saveArt = useMutation({
    mutationFn: () => {
      const payload = { title: artTitle.trim(), body: artBody, kb_category_id: artCategory, sort_order: Number(artSort) || 0, is_published: artPublish };
      return editingArt ? updateKbArticle(editingArt.id, payload) : createKbArticle(payload);
    },
    onSuccess: () => {
      invalidateArts();
      notifications.show({ message: editingArt ? 'Article updated.' : 'Article created.', color: 'green' });
      setArtModalOpen(false);
    },
    onError: () => notifications.show({ message: 'Save failed.', color: 'red' }),
  });
  const toggleArtPublish = useMutation({
    mutationFn: (a: KbArticleRow) => updateKbArticle(a.id, { is_published: !a.is_published }),
    onSuccess: () => invalidateArts(),
  });
  const deleteArt = useMutation({
    mutationFn: deleteKbArticle,
    onSuccess: () => { invalidateArts(); notifications.show({ message: 'Article deleted.', color: 'gray' }); },
  });

  const openCatModal = (c: KbCategoryRow | null) => {
    setEditingCat(c);
    setCatName(c?.name ?? '');
    setCatDesc(c?.description ?? '');
    setCatSort(c?.sort_order ?? 0);
    setCatActive(c?.is_active ?? true);
    setCatModalOpen(true);
  };
  const openArtModal = (a: KbArticleRow | null) => {
    setEditingArt(a);
    setArtTitle(a?.title ?? '');
    setArtBody(a?.body ?? '');
    setArtCategory(a?.kb_category_id ?? null);
    setArtSort(a?.sort_order ?? 0);
    setArtPublish(a?.is_published ?? true);
    setArtModalOpen(true);
  };

  const categoryOptions = categories.map((c) => ({ value: c.id, label: c.name }));

  return (
    <Stack>
      <Group gap="xs">
        <IconBook size={22} />
        <Title order={2}>Knowledgebase</Title>
      </Group>

      <Tabs defaultValue="articles">
        <Tabs.List>
          <Tabs.Tab value="articles" leftSection={<IconFileText size={16} />}>Articles</Tabs.Tab>
          <Tabs.Tab value="categories" leftSection={<IconFolder size={16} />}>Categories</Tabs.Tab>
        </Tabs.List>

        {/* ── Articles ────────────────────────────────────────────────── */}
        <Tabs.Panel value="articles" pt="md">
          <Stack>
            <Group justify="flex-end">
              <Button leftSection={<IconPlus size={16} />} onClick={() => openArtModal(null)}>New Article</Button>
            </Group>
            {artLoading ? (
              <Center py="xl"><Loader /></Center>
            ) : articles.length === 0 ? (
              <Center py="xl"><Text c="dimmed">No articles yet — published ones appear in the client portal.</Text></Center>
            ) : (
              <Paper withBorder radius="md">
                <Table highlightOnHover>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Title</Table.Th>
                      <Table.Th>Category</Table.Th>
                      <Table.Th>Views</Table.Th>
                      <Table.Th>Status</Table.Th>
                      <Table.Th></Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {articles.map((a) => (
                      <Table.Tr key={a.id}>
                        <Table.Td>
                          <Text size="sm" fw={600}>{a.title}</Text>
                          <Text size="xs" c="dimmed" lineClamp={1}>{a.body}</Text>
                        </Table.Td>
                        <Table.Td><Text size="xs" c="dimmed">{a.category_name ?? '—'}</Text></Table.Td>
                        <Table.Td><Text size="xs" c="dimmed">{a.views}</Text></Table.Td>
                        <Table.Td>
                          <Badge size="sm" color={a.is_published ? 'green' : 'gray'} variant="light">
                            {a.is_published ? 'Published' : 'Draft'}
                          </Badge>
                        </Table.Td>
                        <Table.Td>
                          <Group gap={4} justify="flex-end">
                            <Tooltip label={a.is_published ? 'Unpublish' : 'Publish'}>
                              <ActionIcon variant="light" color={a.is_published ? 'gray' : 'green'}
                                onClick={() => toggleArtPublish.mutate(a)}>
                                {a.is_published ? <IconEyeOff size={15} /> : <IconEye size={15} />}
                              </ActionIcon>
                            </Tooltip>
                            <ActionIcon variant="light" onClick={() => openArtModal(a)}><IconEdit size={15} /></ActionIcon>
                            <ActionIcon variant="light" color="red" onClick={() => deleteArt.mutate(a.id)}><IconTrash size={15} /></ActionIcon>
                          </Group>
                        </Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Paper>
            )}
          </Stack>
        </Tabs.Panel>

        {/* ── Categories ──────────────────────────────────────────────── */}
        <Tabs.Panel value="categories" pt="md">
          <Stack>
            <Group justify="flex-end">
              <Button leftSection={<IconPlus size={16} />} onClick={() => openCatModal(null)}>New Category</Button>
            </Group>
            {catLoading ? (
              <Center py="xl"><Loader /></Center>
            ) : categories.length === 0 ? (
              <Center py="xl"><Text c="dimmed">No categories yet.</Text></Center>
            ) : (
              <Paper withBorder radius="md">
                <Table highlightOnHover>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Name</Table.Th>
                      <Table.Th>Articles</Table.Th>
                      <Table.Th>Order</Table.Th>
                      <Table.Th>Status</Table.Th>
                      <Table.Th></Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {categories.map((c) => (
                      <Table.Tr key={c.id}>
                        <Table.Td>
                          <Text size="sm" fw={600}>{c.name}</Text>
                          {c.description && <Text size="xs" c="dimmed" lineClamp={1}>{c.description}</Text>}
                        </Table.Td>
                        <Table.Td><Text size="xs" c="dimmed">{c.articles_count}</Text></Table.Td>
                        <Table.Td><Text size="xs" c="dimmed">{c.sort_order}</Text></Table.Td>
                        <Table.Td>
                          <Badge size="sm" color={c.is_active ? 'green' : 'gray'} variant="light">
                            {c.is_active ? 'Active' : 'Hidden'}
                          </Badge>
                        </Table.Td>
                        <Table.Td>
                          <Group gap={4} justify="flex-end">
                            <ActionIcon variant="light" onClick={() => openCatModal(c)}><IconEdit size={15} /></ActionIcon>
                            <ActionIcon variant="light" color="red" onClick={() => deleteCat.mutate(c.id)}><IconTrash size={15} /></ActionIcon>
                          </Group>
                        </Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Paper>
            )}
          </Stack>
        </Tabs.Panel>
      </Tabs>

      {/* ── Article modal ─────────────────────────────────────────────── */}
      <Modal opened={artModalOpen} onClose={() => setArtModalOpen(false)}
        title={editingArt ? 'Edit Article' : 'New Article'} centered size="lg">
        <Stack gap="sm">
          <TextInput label="Title" required value={artTitle} onChange={(e) => setArtTitle(e.currentTarget.value)} />
          <Select label="Category" placeholder="Uncategorized" clearable data={categoryOptions}
            value={artCategory} onChange={setArtCategory} />
          <Textarea label="Body" required minRows={8} autosize maxRows={20}
            placeholder="Write the help article…"
            value={artBody} onChange={(e) => setArtBody(e.currentTarget.value)} />
          <NumberInput label="Sort order" value={artSort} onChange={setArtSort} min={0} />
          <Switch label="Published (visible to clients)" checked={artPublish}
            onChange={(e) => setArtPublish(e.currentTarget.checked)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setArtModalOpen(false)}>Cancel</Button>
            <Button disabled={!artTitle.trim() || !artBody.trim()} loading={saveArt.isPending}
              onClick={() => saveArt.mutate()}>Save</Button>
          </Group>
        </Stack>
      </Modal>

      {/* ── Category modal ────────────────────────────────────────────── */}
      <Modal opened={catModalOpen} onClose={() => setCatModalOpen(false)}
        title={editingCat ? 'Edit Category' : 'New Category'} centered size="md">
        <Stack gap="sm">
          <TextInput label="Name" required value={catName} onChange={(e) => setCatName(e.currentTarget.value)} />
          <Textarea label="Description" minRows={2} autosize maxRows={6}
            value={catDesc} onChange={(e) => setCatDesc(e.currentTarget.value)} />
          <NumberInput label="Sort order" value={catSort} onChange={setCatSort} min={0} />
          <Switch label="Active (visible to clients)" checked={catActive}
            onChange={(e) => setCatActive(e.currentTarget.checked)} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setCatModalOpen(false)}>Cancel</Button>
            <Button disabled={!catName.trim()} loading={saveCat.isPending}
              onClick={() => saveCat.mutate()}>Save</Button>
          </Group>
        </Stack>
      </Modal>
    </Stack>
  );
}
