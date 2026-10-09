class ArchivePage {
  const ArchivePage(this.items, this.nextCursor);
  final List<Map> items;
  final String? nextCursor;
  factory ArchivePage.parse(dynamic response) {
    final data = response is Map && response.containsKey('data')
        ? response['data']
        : response;
    if (data is List) return ArchivePage(data.cast<Map>(), null);
    if (data is! Map || data['items'] is! List) {
      throw const FormatException('Pagina archivio non valida.');
    }
    final cursor = data['nextCursor'];
    if (cursor != null && cursor is! String) {
      throw const FormatException('Cursore archivio non valido.');
    }
    return ArchivePage((data['items'] as List).cast<Map>(), cursor as String?);
  }
}
