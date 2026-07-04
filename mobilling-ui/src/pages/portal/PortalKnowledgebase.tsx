import { useState } from 'react';
import {
  Stack, Paper, Title, Text, Group, LoadingOverlay, Center, TextInput,
  Anchor, Button, Badge, Divider,
} from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconBook, IconSearch, IconArrowLeft, IconEye, IconChevronRight } from '@tabler/icons-react';
import { useDebouncedValue } from '@mantine/hooks';
import { getPortalKnowledgebase, getPortalKbArticle } from '../../api/knowledgebase';
import dayjs from 'dayjs';

export default function PortalKnowledgebase() {
  const [search, setSearch] = useState('');
  const [debounced] = useDebouncedValue(search, 300);
  const [openSlug, setOpenSlug] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['portal-kb', debounced],
    queryFn: () => getPortalKnowledgebase(debounced || undefined),
  });
  const categories = data?.data?.data ?? [];

  const { data: artData, isLoading: artLoading } = useQuery({
    queryKey: ['portal-kb-article', openSlug],
    queryFn: () => getPortalKbArticle(openSlug as string),
    enabled: !!openSlug,
  });
  const article = artData?.data?.data;

  // ── Article reading view ─────────────────────────────────────────────
  if (openSlug) {
    return (
      <Stack gap="lg" pos="relative">
        <LoadingOverlay visible={artLoading} />
        <Button variant="subtle" leftSection={<IconArrowLeft size={16} />}
          w="fit-content" onClick={() => setOpenSlug(null)}>
          Back to Knowledgebase
        </Button>
        {article && (
          <Paper withBorder radius="md" p="xl">
            {article.category_name && (
              <Badge variant="light" mb="sm">{article.category_name}</Badge>
            )}
            <Title order={2} mb={4}>{article.title}</Title>
            <Group gap="lg" mb="lg">
              <Text size="xs" c="dimmed">Updated {dayjs(article.updated_at).format('D MMM YYYY')}</Text>
              <Group gap={4}>
                <IconEye size={14} />
                <Text size="xs" c="dimmed">{article.views} views</Text>
              </Group>
            </Group>
            <Divider mb="lg" />
            <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>{article.body}</Text>
          </Paper>
        )}
      </Stack>
    );
  }

  // ── Browse / search view ─────────────────────────────────────────────
  const hasArticles = categories.some((c) => c.articles.length > 0);

  return (
    <Stack gap="lg" pos="relative">
      <LoadingOverlay visible={isLoading} />
      <Group gap="xs">
        <IconBook size={22} />
        <Title order={3}>Knowledgebase</Title>
      </Group>

      <TextInput
        placeholder="Search help articles…"
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => setSearch(e.currentTarget.value)}
      />

      {!isLoading && !hasArticles && (
        <Center py="xl">
          <Text c="dimmed">{debounced ? 'No articles match your search.' : 'No help articles yet.'}</Text>
        </Center>
      )}

      {categories.filter((c) => c.articles.length > 0).map((cat) => (
        <Paper key={cat.slug} withBorder radius="md" p="lg">
          <Text fw={700} mb={2}>{cat.name}</Text>
          {cat.description && <Text size="xs" c="dimmed" mb="sm">{cat.description}</Text>}
          <Stack gap={0} mt="sm">
            {cat.articles.map((a) => (
              <div key={a.id}>
                <Divider my={4} />
                <Group justify="space-between" wrap="nowrap"
                  style={{ cursor: 'pointer' }} onClick={() => setOpenSlug(a.slug)} py={6}>
                  <div style={{ minWidth: 0 }}>
                    <Anchor size="sm" fw={600} onClick={(e) => { e.preventDefault(); setOpenSlug(a.slug); }}>
                      {a.title}
                    </Anchor>
                    <Text size="xs" c="dimmed" lineClamp={1}>{a.excerpt}</Text>
                  </div>
                  <IconChevronRight size={16} style={{ flexShrink: 0 }} />
                </Group>
              </div>
            ))}
          </Stack>
        </Paper>
      ))}
    </Stack>
  );
}
