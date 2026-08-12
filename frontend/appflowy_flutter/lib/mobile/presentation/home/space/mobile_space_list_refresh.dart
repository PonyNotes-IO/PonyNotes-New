/// Whether the mobile space document list should keep its existing sequence.
///
/// Android keeps the `ViewBloc` list alive and lets its own view listener apply
/// structural changes. Other clients retain the pre-existing SpaceBloc refresh
/// behavior until they are intentionally migrated.
bool mobileSpaceKeepsDocumentListCached({required bool isAndroid}) => isAndroid;
