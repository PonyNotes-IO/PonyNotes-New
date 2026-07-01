enum WhiteboardSourceRank {
  mirror,
  session,
  authority,
}

class WhiteboardVersionLock {
  WhiteboardVersionLock({
    int initialRevision = 0,
    WhiteboardSourceRank initialSourceRank = WhiteboardSourceRank.mirror,
  })  : _revision = initialRevision,
        _sourceRank = initialSourceRank.index;

  int _revision;
  int _sourceRank;

  int get revision => _revision;
  WhiteboardSourceRank get sourceRank => WhiteboardSourceRank.values[_sourceRank];

  int bump() {
    _revision += 1;
    _sourceRank = WhiteboardSourceRank.session.index;
    return _revision;
  }

  void seed(
    int revision, {
    WhiteboardSourceRank sourceRank = WhiteboardSourceRank.authority,
  }) {
    if (_accepts(revision, sourceRank.index)) {
      _revision = revision;
      _sourceRank = sourceRank.index;
    }
  }

  bool shouldAccept(
    int incomingRevision, {
    WhiteboardSourceRank sourceRank = WhiteboardSourceRank.mirror,
  }) {
    return _accepts(incomingRevision, sourceRank.index);
  }

  bool _accepts(int revision, int sourceRank) {
    if (revision > _revision) {
      return true;
    }
    if (revision < _revision) {
      return false;
    }
    return sourceRank >= _sourceRank;
  }
}
