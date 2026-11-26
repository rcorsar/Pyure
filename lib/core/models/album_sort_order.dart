/// Порядок сортировки альбомов во вкладке «Альбомы».
enum AlbumSortOrder {
  artist('По исполнителю'),
  title('По названию');

  const AlbumSortOrder(this.labelRu);

  final String labelRu;
}
