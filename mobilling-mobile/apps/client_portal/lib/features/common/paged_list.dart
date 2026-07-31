import 'package:flutter/material.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

/// Infinite-scroll list over a paginated portal endpoint.
///
/// Owns the whole lifecycle — first load, pull-to-refresh, tail loading,
/// error and empty states — so the invoices and payments screens only supply
/// a fetcher and a row builder. [fetch] receives the 1-based page to load.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage,
    this.separated = true,
    this.padding = const EdgeInsets.all(Spacing.md),
  });

  final Future<Paginated<T>> Function(int page) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;
  final bool separated;
  final EdgeInsets padding;

  @override
  State<PagedListView<T>> createState() => PagedListViewState<T>();
}

class PagedListViewState<T> extends State<PagedListView<T>> {
  final _scroll = ScrollController();

  Paginated<T>? _data;
  bool _loading = false;
  bool _loadingMore = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Public so a parent (e.g. a search field) can force a reload from page 1.
  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.fetch(1);
      if (!mounted) return;
      setState(() => _data = page);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _maybeLoadMore() {
    // Start fetching a screenful before the end so the spinner is rarely seen.
    if (_scroll.position.extentAfter > 400) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    final current = _data;
    final next = current?.nextPage;
    if (next == null || _loadingMore || _loading) return;

    setState(() => _loadingMore = true);
    try {
      final page = await widget.fetch(next);
      if (!mounted) return;
      setState(() => _data = current!.append(page));
    } on ApiException {
      // A failed tail fetch is retried by the next scroll tick; the list the
      // user already has stays usable, so no error state here.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && data == null) {
      return StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load',
        message: _error!.message,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    if (data == null || data.isEmpty) {
      // Empty states still need pull-to-refresh, hence the scrollable shell.
      return RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: StateMessage(
                icon: widget.emptyIcon,
                title: widget.emptyTitle,
                message: widget.emptyMessage,
              ),
            ),
          ),
        ),
      );
    }

    final items = data.items;
    final tailRows = _loadingMore ? 1 : 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: items.length + tailRows,
        separatorBuilder: (context, index) => widget.separated
            ? const SizedBox(height: Spacing.sm)
            : const SizedBox.shrink(),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return widget.itemBuilder(context, items[index]);
        },
      ),
    );
  }
}
