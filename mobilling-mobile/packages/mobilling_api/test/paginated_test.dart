import 'package:flutter_test/flutter_test.dart';
import 'package:mobilling_api/mobilling_api.dart';

class _Doc {
  const _Doc(this.id);
  final String id;

  static _Doc fromJson(Map<String, dynamic> json) => _Doc(json['id'].toString());
}

void main() {
  group('Paginated.fromJson', () {
    test('parses a Laravel paginator envelope', () {
      // Shape returned by PortalDocumentController, which json-encodes the
      // paginator directly.
      final page = Paginated.fromJson({
        'data': [
          {'id': 'a'},
          {'id': 'b'},
        ],
        'current_page': 2,
        'last_page': 4,
        'per_page': 20,
        'total': 73,
      }, _Doc.fromJson);

      expect(page.items.map((d) => d.id), ['a', 'b']);
      expect(page.currentPage, 2);
      expect(page.lastPage, 4);
      expect(page.total, 73);
      expect(page.hasMore, isTrue);
      expect(page.nextPage, 3);
    });

    test('treats a bare {data: []} wrapper as one complete page', () {
      final page = Paginated.fromJson({
        'data': [
          {'id': 'a'},
        ],
      }, _Doc.fromJson);

      expect(page.items, hasLength(1));
      expect(page.currentPage, 1);
      expect(page.hasMore, isFalse);
      expect(page.nextPage, isNull);
    });

    test('accepts a bare JSON array', () {
      final page = Paginated.fromJson([
        {'id': 'a'},
        {'id': 'b'},
      ], _Doc.fromJson);

      expect(page.items, hasLength(2));
      expect(page.total, 2);
      expect(page.hasMore, isFalse);
    });

    test('reads page metadata from a JsonResource::collection `meta` block',
        () {
      // Shape returned by every `Resource::collection(paginate())` endpoint
      // (/documents, /clients, /expenses, /users ...).
      final page = Paginated.fromJson({
        'data': [
          {'id': 'a'},
        ],
        'links': {'first': '…', 'next': '…'},
        'meta': {
          'current_page': 1,
          'last_page': 63,
          'per_page': 20,
          'total': 1246,
        },
      }, _Doc.fromJson);

      expect(page.items.single.id, 'a');
      expect(page.currentPage, 1);
      expect(page.lastPage, 63);
      expect(page.total, 1246);
      expect(page.hasMore, isTrue);
      expect(page.nextPage, 2);
    });

    test('coerces numeric strings in page metadata', () {
      // per_page arrives as a string when it came straight from a query param.
      final page = Paginated.fromJson({
        'data': <dynamic>[],
        'current_page': 1,
        'last_page': '3',
        'per_page': '20',
        'total': '55',
      }, _Doc.fromJson);

      expect(page.lastPage, 3);
      expect(page.perPage, 20);
      expect(page.total, 55);
      expect(page.hasMore, isTrue);
    });

    test('survives a malformed body without throwing', () {
      final page = Paginated.fromJson('nonsense', _Doc.fromJson);
      expect(page.isEmpty, isTrue);
      expect(page.hasMore, isFalse);
    });

    test('last page reports no more results', () {
      final page = Paginated.fromJson({
        'data': <dynamic>[],
        'current_page': 4,
        'last_page': 4,
        'total': 73,
      }, _Doc.fromJson);

      expect(page.hasMore, isFalse);
      expect(page.nextPage, isNull);
    });
  });

  group('Paginated.append', () {
    test('concatenates items and adopts the newer page metadata', () {
      final first = Paginated<_Doc>(
        items: const [_Doc('a')],
        currentPage: 1,
        lastPage: 3,
        total: 3,
        perPage: 1,
      );
      final second = Paginated<_Doc>(
        items: const [_Doc('b')],
        currentPage: 2,
        lastPage: 3,
        total: 3,
        perPage: 1,
      );

      final combined = first.append(second);

      expect(combined.items.map((d) => d.id), ['a', 'b']);
      expect(combined.currentPage, 2);
      expect(combined.hasMore, isTrue);
    });
  });
}
