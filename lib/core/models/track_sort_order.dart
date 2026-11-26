/// Порядок сортировки списка треков во вкладке «Треки».
enum TrackSortOrder {
  title('По названию'),
  album('По альбому'),
  addedAt('По дате добавления');

  const TrackSortOrder(this.labelRu);

  final String labelRu;
}
