class WhiteboardVersionLock {
  WhiteboardVersionLock({
    int initialRevision = 0,
  }) : _revision = initialRevision;

  int _revision;

  int get revision => _revision;

  int bump() {
    _revision += 1;
    return _revision;
  }

  void seed(int revision) {
    if (revision > _revision) {
      _revision = revision;
    }
  }

  bool shouldAccept(int incomingRevision) {
    return incomingRevision >= _revision;
  }
}
