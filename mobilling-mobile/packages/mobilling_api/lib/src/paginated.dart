/// A page of results from the MoBilling API.
///
/// The backend is inconsistent about envelopes, and rather than fix ~56 live
/// endpoints we absorb the difference here, once:
///
///   * Paginated routes return Laravel's paginator verbatim — e.g.
///     `PortalDocumentController` does `response()->json($paginated)`, giving
///     `{data: [...], current_page: 1, last_page: 4, per_page: 20, total: 73}`.
///   * Unpaginated routes return `{data: [...]}` with no page metadata.
///   * A few return a bare JSON array.
///
/// All three parse into this type. When metadata is absent the payload is
/// treated as a single complete page, so `hasMore` is false and paging logic
/// upstream does not need to special-case it.
class Paginated<T> {
  const Paginated({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    this.perPage,
  });

  final List<T> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final int? perPage;

  /// True when at least one more page exists after this one.
  bool get hasMore => currentPage < lastPage;

  bool get isEmpty => items.isEmpty;

  /// Page number to request next, or null at the end of the list.
  int? get nextPage => hasMore ? currentPage + 1 : null;

  /// A complete, unpaginated result set.
  factory Paginated.single(List<T> items) => Paginated(
        items: items,
        currentPage: 1,
        lastPage: 1,
        total: items.length,
      );

  /// Parse any of the three envelope shapes described above.
  ///
  /// [fromJson] converts one element; it is called per item so callers supply
  /// their own model constructors.
  factory Paginated.fromJson(
    dynamic body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    List<T> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    // Bare array — no envelope at all.
    if (body is List) return Paginated.single(parseList(body));

    if (body is! Map) return Paginated.single(const []);

    final items = parseList(body['data']);

    // `current_page` is the marker that this is a real Laravel paginator;
    // without it we only have a wrapped list. A `JsonResource::collection`
    // response (most staff list endpoints) puts that metadata under `meta`
    // rather than at the top level — missing that silently capped every
    // such list at its first page.
    final rawMeta = body['meta'];
    final meta = rawMeta is Map && rawMeta['current_page'] != null
        ? Map<String, dynamic>.from(rawMeta)
        : body;
    final currentPage = _asInt(meta['current_page']);
    if (currentPage == null) return Paginated.single(items);

    return Paginated(
      items: items,
      currentPage: currentPage,
      lastPage: _asInt(meta['last_page']) ?? currentPage,
      total: _asInt(meta['total']) ?? items.length,
      perPage: _asInt(meta['per_page']),
    );
  }

  /// Append a later page onto this one, preserving that page's metadata.
  /// Used by infinite-scroll lists.
  Paginated<T> append(Paginated<T> next) => Paginated(
        items: [...items, ...next.items],
        currentPage: next.currentPage,
        lastPage: next.lastPage,
        total: next.total,
        perPage: next.perPage ?? perPage,
      );

  /// `per_page` arrives as an int from the paginator but as a numeric string
  /// from a few hand-rolled endpoints, so accept both.
  static int? _asInt(dynamic value) => switch (value) {
        int v => v,
        String v => int.tryParse(v),
        num v => v.toInt(),
        _ => null,
      };
}
