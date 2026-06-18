///
//  Generated code. Do not modify.
//  source: view.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'icon.pb.dart' as $0;

import 'view.pbenum.dart';

export 'view.pbenum.dart';

class ChildViewUpdatePB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ChildViewUpdatePB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'parentViewId')
    ..pc<ViewPB>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'createChildViews', $pb.PbFieldType.PM, subBuilder: ViewPB.create)
    ..pPS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'deleteChildViews')
    ..pc<ViewPB>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'updateChildViews', $pb.PbFieldType.PM, subBuilder: ViewPB.create)
    ..hasRequiredFields = false
  ;

  ChildViewUpdatePB._() : super();
  factory ChildViewUpdatePB({
    $core.String? parentViewId,
    $core.Iterable<ViewPB>? createChildViews,
    $core.Iterable<$core.String>? deleteChildViews,
    $core.Iterable<ViewPB>? updateChildViews,
  }) {
    final _result = create();
    if (parentViewId != null) {
      _result.parentViewId = parentViewId;
    }
    if (createChildViews != null) {
      _result.createChildViews.addAll(createChildViews);
    }
    if (deleteChildViews != null) {
      _result.deleteChildViews.addAll(deleteChildViews);
    }
    if (updateChildViews != null) {
      _result.updateChildViews.addAll(updateChildViews);
    }
    return _result;
  }
  factory ChildViewUpdatePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChildViewUpdatePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChildViewUpdatePB clone() => ChildViewUpdatePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChildViewUpdatePB copyWith(void Function(ChildViewUpdatePB) updates) => super.copyWith((message) => updates(message as ChildViewUpdatePB)) as ChildViewUpdatePB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ChildViewUpdatePB create() => ChildViewUpdatePB._();
  ChildViewUpdatePB createEmptyInstance() => create();
  static $pb.PbList<ChildViewUpdatePB> createRepeated() => $pb.PbList<ChildViewUpdatePB>();
  @$core.pragma('dart2js:noInline')
  static ChildViewUpdatePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChildViewUpdatePB>(create);
  static ChildViewUpdatePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get parentViewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set parentViewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasParentViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearParentViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ViewPB> get createChildViews => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<$core.String> get deleteChildViews => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<ViewPB> get updateChildViews => $_getList(3);
}

enum ViewPB_OneOfIcon {
  icon, 
  notSet
}

enum ViewPB_OneOfExtra {
  extra, 
  notSet
}

enum ViewPB_OneOfCreatedBy {
  createdBy, 
  notSet
}

enum ViewPB_OneOfLastEditedBy {
  lastEditedBy, 
  notSet
}

enum ViewPB_OneOfIsLocked {
  isLocked, 
  notSet
}

enum ViewPB_OneOfWorkspaceId {
  workspaceId, 
  notSet
}

class ViewPB extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, ViewPB_OneOfIcon> _ViewPB_OneOfIconByTag = {
    7 : ViewPB_OneOfIcon.icon,
    0 : ViewPB_OneOfIcon.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfExtra> _ViewPB_OneOfExtraByTag = {
    9 : ViewPB_OneOfExtra.extra,
    0 : ViewPB_OneOfExtra.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfCreatedBy> _ViewPB_OneOfCreatedByByTag = {
    10 : ViewPB_OneOfCreatedBy.createdBy,
    0 : ViewPB_OneOfCreatedBy.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfLastEditedBy> _ViewPB_OneOfLastEditedByByTag = {
    12 : ViewPB_OneOfLastEditedBy.lastEditedBy,
    0 : ViewPB_OneOfLastEditedBy.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfIsLocked> _ViewPB_OneOfIsLockedByTag = {
    13 : ViewPB_OneOfIsLocked.isLocked,
    0 : ViewPB_OneOfIsLocked.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfWorkspaceId> _ViewPB_OneOfWorkspaceIdByTag = {
    14 : ViewPB_OneOfWorkspaceId.workspaceId,
    0 : ViewPB_OneOfWorkspaceId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ViewPB', createEmptyInstance: create)
    ..oo(0, [7])
    ..oo(1, [9])
    ..oo(2, [10])
    ..oo(3, [12])
    ..oo(4, [13])
    ..oo(5, [14])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'id')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'parentViewId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'createTime')
    ..pc<ViewPB>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'childViews', $pb.PbFieldType.PM, subBuilder: ViewPB.create)
    ..e<ViewLayoutPB>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'layout', $pb.PbFieldType.OE, defaultOrMaker: ViewLayoutPB.Document, valueOf: ViewLayoutPB.valueOf, enumValues: ViewLayoutPB.values)
    ..aOM<$0.ViewIconPB>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'icon', subBuilder: $0.ViewIconPB.create)
    ..aOB(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isFavorite')
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'extra')
    ..aInt64(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'createdBy')
    ..aInt64(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'lastEdited')
    ..aInt64(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'lastEditedBy')
    ..aOB(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isLocked')
    ..aOS(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'workspaceId')
    ..hasRequiredFields = false
  ;

  ViewPB._() : super();
  factory ViewPB({
    $core.String? id,
    $core.String? parentViewId,
    $core.String? name,
    $fixnum.Int64? createTime,
    $core.Iterable<ViewPB>? childViews,
    ViewLayoutPB? layout,
    $0.ViewIconPB? icon,
    $core.bool? isFavorite,
    $core.String? extra,
    $fixnum.Int64? createdBy,
    $fixnum.Int64? lastEdited,
    $fixnum.Int64? lastEditedBy,
    $core.bool? isLocked,
    $core.String? workspaceId,
  }) {
    final _result = create();
    if (id != null) {
      _result.id = id;
    }
    if (parentViewId != null) {
      _result.parentViewId = parentViewId;
    }
    if (name != null) {
      _result.name = name;
    }
    if (createTime != null) {
      _result.createTime = createTime;
    }
    if (childViews != null) {
      _result.childViews.addAll(childViews);
    }
    if (layout != null) {
      _result.layout = layout;
    }
    if (icon != null) {
      _result.icon = icon;
    }
    if (isFavorite != null) {
      _result.isFavorite = isFavorite;
    }
    if (extra != null) {
      _result.extra = extra;
    }
    if (createdBy != null) {
      _result.createdBy = createdBy;
    }
    if (lastEdited != null) {
      _result.lastEdited = lastEdited;
    }
    if (lastEditedBy != null) {
      _result.lastEditedBy = lastEditedBy;
    }
    if (isLocked != null) {
      _result.isLocked = isLocked;
    }
    if (workspaceId != null) {
      _result.workspaceId = workspaceId;
    }
    return _result;
  }
  factory ViewPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ViewPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ViewPB clone() => ViewPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ViewPB copyWith(void Function(ViewPB) updates) => super.copyWith((message) => updates(message as ViewPB)) as ViewPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ViewPB create() => ViewPB._();
  ViewPB createEmptyInstance() => create();
  static $pb.PbList<ViewPB> createRepeated() => $pb.PbList<ViewPB>();
  @$core.pragma('dart2js:noInline')
  static ViewPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ViewPB>(create);
  static ViewPB? _defaultInstance;

  ViewPB_OneOfIcon whichOneOfIcon() => _ViewPB_OneOfIconByTag[$_whichOneof(0)]!;
  void clearOneOfIcon() => clearField($_whichOneof(0));

  ViewPB_OneOfExtra whichOneOfExtra() => _ViewPB_OneOfExtraByTag[$_whichOneof(1)]!;
  void clearOneOfExtra() => clearField($_whichOneof(1));

  ViewPB_OneOfCreatedBy whichOneOfCreatedBy() => _ViewPB_OneOfCreatedByByTag[$_whichOneof(2)]!;
  void clearOneOfCreatedBy() => clearField($_whichOneof(2));

  ViewPB_OneOfLastEditedBy whichOneOfLastEditedBy() => _ViewPB_OneOfLastEditedByByTag[$_whichOneof(3)]!;
  void clearOneOfLastEditedBy() => clearField($_whichOneof(3));

  ViewPB_OneOfIsLocked whichOneOfIsLocked() => _ViewPB_OneOfIsLockedByTag[$_whichOneof(4)]!;
  void clearOneOfIsLocked() => clearField($_whichOneof(4));

  ViewPB_OneOfWorkspaceId whichOneOfWorkspaceId() => _ViewPB_OneOfWorkspaceIdByTag[$_whichOneof(5)]!;
  void clearOneOfWorkspaceId() => clearField($_whichOneof(5));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get parentViewId => $_getSZ(1);
  @$pb.TagNumber(2)
  set parentViewId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasParentViewId() => $_has(1);
  @$pb.TagNumber(2)
  void clearParentViewId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get createTime => $_getI64(3);
  @$pb.TagNumber(4)
  set createTime($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCreateTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearCreateTime() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<ViewPB> get childViews => $_getList(4);

  @$pb.TagNumber(6)
  ViewLayoutPB get layout => $_getN(5);
  @$pb.TagNumber(6)
  set layout(ViewLayoutPB v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasLayout() => $_has(5);
  @$pb.TagNumber(6)
  void clearLayout() => clearField(6);

  @$pb.TagNumber(7)
  $0.ViewIconPB get icon => $_getN(6);
  @$pb.TagNumber(7)
  set icon($0.ViewIconPB v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasIcon() => $_has(6);
  @$pb.TagNumber(7)
  void clearIcon() => clearField(7);
  @$pb.TagNumber(7)
  $0.ViewIconPB ensureIcon() => $_ensure(6);

  @$pb.TagNumber(8)
  $core.bool get isFavorite => $_getBF(7);
  @$pb.TagNumber(8)
  set isFavorite($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasIsFavorite() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsFavorite() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get extra => $_getSZ(8);
  @$pb.TagNumber(9)
  set extra($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasExtra() => $_has(8);
  @$pb.TagNumber(9)
  void clearExtra() => clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get createdBy => $_getI64(9);
  @$pb.TagNumber(10)
  set createdBy($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasCreatedBy() => $_has(9);
  @$pb.TagNumber(10)
  void clearCreatedBy() => clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get lastEdited => $_getI64(10);
  @$pb.TagNumber(11)
  set lastEdited($fixnum.Int64 v) { $_setInt64(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasLastEdited() => $_has(10);
  @$pb.TagNumber(11)
  void clearLastEdited() => clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get lastEditedBy => $_getI64(11);
  @$pb.TagNumber(12)
  set lastEditedBy($fixnum.Int64 v) { $_setInt64(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasLastEditedBy() => $_has(11);
  @$pb.TagNumber(12)
  void clearLastEditedBy() => clearField(12);

  @$pb.TagNumber(13)
  $core.bool get isLocked => $_getBF(12);
  @$pb.TagNumber(13)
  set isLocked($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasIsLocked() => $_has(12);
  @$pb.TagNumber(13)
  void clearIsLocked() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get workspaceId => $_getSZ(13);
  @$pb.TagNumber(14)
  set workspaceId($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasWorkspaceId() => $_has(13);
  @$pb.TagNumber(14)
  void clearWorkspaceId() => clearField(14);
}

class SectionViewsPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SectionViewsPB', createEmptyInstance: create)
    ..e<ViewSectionPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'section', $pb.PbFieldType.OE, defaultOrMaker: ViewSectionPB.Private, valueOf: ViewSectionPB.valueOf, enumValues: ViewSectionPB.values)
    ..pc<ViewPB>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'views', $pb.PbFieldType.PM, subBuilder: ViewPB.create)
    ..hasRequiredFields = false
  ;

  SectionViewsPB._() : super();
  factory SectionViewsPB({
    ViewSectionPB? section,
    $core.Iterable<ViewPB>? views,
  }) {
    final _result = create();
    if (section != null) {
      _result.section = section;
    }
    if (views != null) {
      _result.views.addAll(views);
    }
    return _result;
  }
  factory SectionViewsPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SectionViewsPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SectionViewsPB clone() => SectionViewsPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SectionViewsPB copyWith(void Function(SectionViewsPB) updates) => super.copyWith((message) => updates(message as SectionViewsPB)) as SectionViewsPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SectionViewsPB create() => SectionViewsPB._();
  SectionViewsPB createEmptyInstance() => create();
  static $pb.PbList<SectionViewsPB> createRepeated() => $pb.PbList<SectionViewsPB>();
  @$core.pragma('dart2js:noInline')
  static SectionViewsPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SectionViewsPB>(create);
  static SectionViewsPB? _defaultInstance;

  @$pb.TagNumber(1)
  ViewSectionPB get section => $_getN(0);
  @$pb.TagNumber(1)
  set section(ViewSectionPB v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasSection() => $_has(0);
  @$pb.TagNumber(1)
  void clearSection() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ViewPB> get views => $_getList(1);
}

class RepeatedViewPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RepeatedViewPB', createEmptyInstance: create)
    ..pc<ViewPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'items', $pb.PbFieldType.PM, subBuilder: ViewPB.create)
    ..hasRequiredFields = false
  ;

  RepeatedViewPB._() : super();
  factory RepeatedViewPB({
    $core.Iterable<ViewPB>? items,
  }) {
    final _result = create();
    if (items != null) {
      _result.items.addAll(items);
    }
    return _result;
  }
  factory RepeatedViewPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedViewPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedViewPB clone() => RepeatedViewPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedViewPB copyWith(void Function(RepeatedViewPB) updates) => super.copyWith((message) => updates(message as RepeatedViewPB)) as RepeatedViewPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RepeatedViewPB create() => RepeatedViewPB._();
  RepeatedViewPB createEmptyInstance() => create();
  static $pb.PbList<RepeatedViewPB> createRepeated() => $pb.PbList<RepeatedViewPB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedViewPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedViewPB>(create);
  static RepeatedViewPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<ViewPB> get items => $_getList(0);
}

class RepeatedFavoriteViewPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RepeatedFavoriteViewPB', createEmptyInstance: create)
    ..pc<SectionViewPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'items', $pb.PbFieldType.PM, subBuilder: SectionViewPB.create)
    ..hasRequiredFields = false
  ;

  RepeatedFavoriteViewPB._() : super();
  factory RepeatedFavoriteViewPB({
    $core.Iterable<SectionViewPB>? items,
  }) {
    final _result = create();
    if (items != null) {
      _result.items.addAll(items);
    }
    return _result;
  }
  factory RepeatedFavoriteViewPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedFavoriteViewPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedFavoriteViewPB clone() => RepeatedFavoriteViewPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedFavoriteViewPB copyWith(void Function(RepeatedFavoriteViewPB) updates) => super.copyWith((message) => updates(message as RepeatedFavoriteViewPB)) as RepeatedFavoriteViewPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RepeatedFavoriteViewPB create() => RepeatedFavoriteViewPB._();
  RepeatedFavoriteViewPB createEmptyInstance() => create();
  static $pb.PbList<RepeatedFavoriteViewPB> createRepeated() => $pb.PbList<RepeatedFavoriteViewPB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedFavoriteViewPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedFavoriteViewPB>(create);
  static RepeatedFavoriteViewPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<SectionViewPB> get items => $_getList(0);
}

class ReadRecentViewsPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ReadRecentViewsPB', createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'start', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'limit', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false
  ;

  ReadRecentViewsPB._() : super();
  factory ReadRecentViewsPB({
    $fixnum.Int64? start,
    $fixnum.Int64? limit,
  }) {
    final _result = create();
    if (start != null) {
      _result.start = start;
    }
    if (limit != null) {
      _result.limit = limit;
    }
    return _result;
  }
  factory ReadRecentViewsPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ReadRecentViewsPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ReadRecentViewsPB clone() => ReadRecentViewsPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ReadRecentViewsPB copyWith(void Function(ReadRecentViewsPB) updates) => super.copyWith((message) => updates(message as ReadRecentViewsPB)) as ReadRecentViewsPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ReadRecentViewsPB create() => ReadRecentViewsPB._();
  ReadRecentViewsPB createEmptyInstance() => create();
  static $pb.PbList<ReadRecentViewsPB> createRepeated() => $pb.PbList<ReadRecentViewsPB>();
  @$core.pragma('dart2js:noInline')
  static ReadRecentViewsPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReadRecentViewsPB>(create);
  static ReadRecentViewsPB? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get start => $_getI64(0);
  @$pb.TagNumber(1)
  set start($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearStart() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get limit => $_getI64(1);
  @$pb.TagNumber(2)
  set limit($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => clearField(2);
}

class RepeatedRecentViewPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RepeatedRecentViewPB', createEmptyInstance: create)
    ..pc<SectionViewPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'items', $pb.PbFieldType.PM, subBuilder: SectionViewPB.create)
    ..hasRequiredFields = false
  ;

  RepeatedRecentViewPB._() : super();
  factory RepeatedRecentViewPB({
    $core.Iterable<SectionViewPB>? items,
  }) {
    final _result = create();
    if (items != null) {
      _result.items.addAll(items);
    }
    return _result;
  }
  factory RepeatedRecentViewPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedRecentViewPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedRecentViewPB clone() => RepeatedRecentViewPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedRecentViewPB copyWith(void Function(RepeatedRecentViewPB) updates) => super.copyWith((message) => updates(message as RepeatedRecentViewPB)) as RepeatedRecentViewPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RepeatedRecentViewPB create() => RepeatedRecentViewPB._();
  RepeatedRecentViewPB createEmptyInstance() => create();
  static $pb.PbList<RepeatedRecentViewPB> createRepeated() => $pb.PbList<RepeatedRecentViewPB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedRecentViewPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedRecentViewPB>(create);
  static RepeatedRecentViewPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<SectionViewPB> get items => $_getList(0);
}

class SectionViewPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SectionViewPB', createEmptyInstance: create)
    ..aOM<ViewPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'item', subBuilder: ViewPB.create)
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'timestamp')
    ..hasRequiredFields = false
  ;

  SectionViewPB._() : super();
  factory SectionViewPB({
    ViewPB? item,
    $fixnum.Int64? timestamp,
  }) {
    final _result = create();
    if (item != null) {
      _result.item = item;
    }
    if (timestamp != null) {
      _result.timestamp = timestamp;
    }
    return _result;
  }
  factory SectionViewPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SectionViewPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SectionViewPB clone() => SectionViewPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SectionViewPB copyWith(void Function(SectionViewPB) updates) => super.copyWith((message) => updates(message as SectionViewPB)) as SectionViewPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SectionViewPB create() => SectionViewPB._();
  SectionViewPB createEmptyInstance() => create();
  static $pb.PbList<SectionViewPB> createRepeated() => $pb.PbList<SectionViewPB>();
  @$core.pragma('dart2js:noInline')
  static SectionViewPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SectionViewPB>(create);
  static SectionViewPB? _defaultInstance;

  @$pb.TagNumber(1)
  ViewPB get item => $_getN(0);
  @$pb.TagNumber(1)
  set item(ViewPB v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasItem() => $_has(0);
  @$pb.TagNumber(1)
  void clearItem() => clearField(1);
  @$pb.TagNumber(1)
  ViewPB ensureItem() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => clearField(2);
}

class RepeatedViewIdPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RepeatedViewIdPB', createEmptyInstance: create)
    ..pPS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'items')
    ..hasRequiredFields = false
  ;

  RepeatedViewIdPB._() : super();
  factory RepeatedViewIdPB({
    $core.Iterable<$core.String>? items,
  }) {
    final _result = create();
    if (items != null) {
      _result.items.addAll(items);
    }
    return _result;
  }
  factory RepeatedViewIdPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedViewIdPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedViewIdPB clone() => RepeatedViewIdPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedViewIdPB copyWith(void Function(RepeatedViewIdPB) updates) => super.copyWith((message) => updates(message as RepeatedViewIdPB)) as RepeatedViewIdPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RepeatedViewIdPB create() => RepeatedViewIdPB._();
  RepeatedViewIdPB createEmptyInstance() => create();
  static $pb.PbList<RepeatedViewIdPB> createRepeated() => $pb.PbList<RepeatedViewIdPB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedViewIdPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedViewIdPB>(create);
  static RepeatedViewIdPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get items => $_getList(0);
}

enum CreateViewPayloadPB_OneOfThumbnail {
  thumbnail, 
  notSet
}

enum CreateViewPayloadPB_OneOfIndex {
  index_, 
  notSet
}

enum CreateViewPayloadPB_OneOfSection {
  section, 
  notSet
}

enum CreateViewPayloadPB_OneOfViewId {
  viewId, 
  notSet
}

enum CreateViewPayloadPB_OneOfExtra {
  extra, 
  notSet
}

class CreateViewPayloadPB extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfThumbnail> _CreateViewPayloadPB_OneOfThumbnailByTag = {
    3 : CreateViewPayloadPB_OneOfThumbnail.thumbnail,
    0 : CreateViewPayloadPB_OneOfThumbnail.notSet
  };
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfIndex> _CreateViewPayloadPB_OneOfIndexByTag = {
    8 : CreateViewPayloadPB_OneOfIndex.index_,
    0 : CreateViewPayloadPB_OneOfIndex.notSet
  };
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfSection> _CreateViewPayloadPB_OneOfSectionByTag = {
    9 : CreateViewPayloadPB_OneOfSection.section,
    0 : CreateViewPayloadPB_OneOfSection.notSet
  };
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfViewId> _CreateViewPayloadPB_OneOfViewIdByTag = {
    10 : CreateViewPayloadPB_OneOfViewId.viewId,
    0 : CreateViewPayloadPB_OneOfViewId.notSet
  };
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfExtra> _CreateViewPayloadPB_OneOfExtraByTag = {
    11 : CreateViewPayloadPB_OneOfExtra.extra,
    0 : CreateViewPayloadPB_OneOfExtra.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'CreateViewPayloadPB', createEmptyInstance: create)
    ..oo(0, [3])
    ..oo(1, [8])
    ..oo(2, [9])
    ..oo(3, [10])
    ..oo(4, [11])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'parentViewId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thumbnail')
    ..e<ViewLayoutPB>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'layout', $pb.PbFieldType.OE, defaultOrMaker: ViewLayoutPB.Document, valueOf: ViewLayoutPB.valueOf, enumValues: ViewLayoutPB.values)
    ..a<$core.List<$core.int>>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'initialData', $pb.PbFieldType.OY)
    ..m<$core.String, $core.String>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'meta', entryClassName: 'CreateViewPayloadPB.MetaEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS)
    ..aOB(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'setAsCurrent')
    ..a<$core.int>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'index', $pb.PbFieldType.OU3)
    ..e<ViewSectionPB>(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'section', $pb.PbFieldType.OE, defaultOrMaker: ViewSectionPB.Private, valueOf: ViewSectionPB.valueOf, enumValues: ViewSectionPB.values)
    ..aOS(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..aOS(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'extra')
    ..hasRequiredFields = false
  ;

  CreateViewPayloadPB._() : super();
  factory CreateViewPayloadPB({
    $core.String? parentViewId,
    $core.String? name,
    $core.String? thumbnail,
    ViewLayoutPB? layout,
    $core.List<$core.int>? initialData,
    $core.Map<$core.String, $core.String>? meta,
    $core.bool? setAsCurrent,
    $core.int? index,
    ViewSectionPB? section,
    $core.String? viewId,
    $core.String? extra,
  }) {
    final _result = create();
    if (parentViewId != null) {
      _result.parentViewId = parentViewId;
    }
    if (name != null) {
      _result.name = name;
    }
    if (thumbnail != null) {
      _result.thumbnail = thumbnail;
    }
    if (layout != null) {
      _result.layout = layout;
    }
    if (initialData != null) {
      _result.initialData = initialData;
    }
    if (meta != null) {
      _result.meta.addAll(meta);
    }
    if (setAsCurrent != null) {
      _result.setAsCurrent = setAsCurrent;
    }
    if (index != null) {
      _result.index = index;
    }
    if (section != null) {
      _result.section = section;
    }
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (extra != null) {
      _result.extra = extra;
    }
    return _result;
  }
  factory CreateViewPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CreateViewPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CreateViewPayloadPB clone() => CreateViewPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CreateViewPayloadPB copyWith(void Function(CreateViewPayloadPB) updates) => super.copyWith((message) => updates(message as CreateViewPayloadPB)) as CreateViewPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static CreateViewPayloadPB create() => CreateViewPayloadPB._();
  CreateViewPayloadPB createEmptyInstance() => create();
  static $pb.PbList<CreateViewPayloadPB> createRepeated() => $pb.PbList<CreateViewPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static CreateViewPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateViewPayloadPB>(create);
  static CreateViewPayloadPB? _defaultInstance;

  CreateViewPayloadPB_OneOfThumbnail whichOneOfThumbnail() => _CreateViewPayloadPB_OneOfThumbnailByTag[$_whichOneof(0)]!;
  void clearOneOfThumbnail() => clearField($_whichOneof(0));

  CreateViewPayloadPB_OneOfIndex whichOneOfIndex() => _CreateViewPayloadPB_OneOfIndexByTag[$_whichOneof(1)]!;
  void clearOneOfIndex() => clearField($_whichOneof(1));

  CreateViewPayloadPB_OneOfSection whichOneOfSection() => _CreateViewPayloadPB_OneOfSectionByTag[$_whichOneof(2)]!;
  void clearOneOfSection() => clearField($_whichOneof(2));

  CreateViewPayloadPB_OneOfViewId whichOneOfViewId() => _CreateViewPayloadPB_OneOfViewIdByTag[$_whichOneof(3)]!;
  void clearOneOfViewId() => clearField($_whichOneof(3));

  CreateViewPayloadPB_OneOfExtra whichOneOfExtra() => _CreateViewPayloadPB_OneOfExtraByTag[$_whichOneof(4)]!;
  void clearOneOfExtra() => clearField($_whichOneof(4));

  @$pb.TagNumber(1)
  $core.String get parentViewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set parentViewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasParentViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearParentViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get thumbnail => $_getSZ(2);
  @$pb.TagNumber(3)
  set thumbnail($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasThumbnail() => $_has(2);
  @$pb.TagNumber(3)
  void clearThumbnail() => clearField(3);

  @$pb.TagNumber(4)
  ViewLayoutPB get layout => $_getN(3);
  @$pb.TagNumber(4)
  set layout(ViewLayoutPB v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasLayout() => $_has(3);
  @$pb.TagNumber(4)
  void clearLayout() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get initialData => $_getN(4);
  @$pb.TagNumber(5)
  set initialData($core.List<$core.int> v) { $_setBytes(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasInitialData() => $_has(4);
  @$pb.TagNumber(5)
  void clearInitialData() => clearField(5);

  @$pb.TagNumber(6)
  $core.Map<$core.String, $core.String> get meta => $_getMap(5);

  @$pb.TagNumber(7)
  $core.bool get setAsCurrent => $_getBF(6);
  @$pb.TagNumber(7)
  set setAsCurrent($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSetAsCurrent() => $_has(6);
  @$pb.TagNumber(7)
  void clearSetAsCurrent() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get index => $_getIZ(7);
  @$pb.TagNumber(8)
  set index($core.int v) { $_setUnsignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasIndex() => $_has(7);
  @$pb.TagNumber(8)
  void clearIndex() => clearField(8);

  @$pb.TagNumber(9)
  ViewSectionPB get section => $_getN(8);
  @$pb.TagNumber(9)
  set section(ViewSectionPB v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasSection() => $_has(8);
  @$pb.TagNumber(9)
  void clearSection() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get viewId => $_getSZ(9);
  @$pb.TagNumber(10)
  set viewId($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasViewId() => $_has(9);
  @$pb.TagNumber(10)
  void clearViewId() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get extra => $_getSZ(10);
  @$pb.TagNumber(11)
  set extra($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasExtra() => $_has(10);
  @$pb.TagNumber(11)
  void clearExtra() => clearField(11);
}

class CreateOrphanViewPayloadPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'CreateOrphanViewPayloadPB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..e<ViewLayoutPB>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'layout', $pb.PbFieldType.OE, defaultOrMaker: ViewLayoutPB.Document, valueOf: ViewLayoutPB.valueOf, enumValues: ViewLayoutPB.values)
    ..a<$core.List<$core.int>>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'initialData', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  CreateOrphanViewPayloadPB._() : super();
  factory CreateOrphanViewPayloadPB({
    $core.String? viewId,
    $core.String? name,
    ViewLayoutPB? layout,
    $core.List<$core.int>? initialData,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (name != null) {
      _result.name = name;
    }
    if (layout != null) {
      _result.layout = layout;
    }
    if (initialData != null) {
      _result.initialData = initialData;
    }
    return _result;
  }
  factory CreateOrphanViewPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CreateOrphanViewPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CreateOrphanViewPayloadPB clone() => CreateOrphanViewPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CreateOrphanViewPayloadPB copyWith(void Function(CreateOrphanViewPayloadPB) updates) => super.copyWith((message) => updates(message as CreateOrphanViewPayloadPB)) as CreateOrphanViewPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static CreateOrphanViewPayloadPB create() => CreateOrphanViewPayloadPB._();
  CreateOrphanViewPayloadPB createEmptyInstance() => create();
  static $pb.PbList<CreateOrphanViewPayloadPB> createRepeated() => $pb.PbList<CreateOrphanViewPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static CreateOrphanViewPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateOrphanViewPayloadPB>(create);
  static CreateOrphanViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  ViewLayoutPB get layout => $_getN(2);
  @$pb.TagNumber(3)
  set layout(ViewLayoutPB v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasLayout() => $_has(2);
  @$pb.TagNumber(3)
  void clearLayout() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get initialData => $_getN(3);
  @$pb.TagNumber(4)
  set initialData($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasInitialData() => $_has(3);
  @$pb.TagNumber(4)
  void clearInitialData() => clearField(4);
}

class ViewIdPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ViewIdPB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'value')
    ..hasRequiredFields = false
  ;

  ViewIdPB._() : super();
  factory ViewIdPB({
    $core.String? value,
  }) {
    final _result = create();
    if (value != null) {
      _result.value = value;
    }
    return _result;
  }
  factory ViewIdPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ViewIdPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ViewIdPB clone() => ViewIdPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ViewIdPB copyWith(void Function(ViewIdPB) updates) => super.copyWith((message) => updates(message as ViewIdPB)) as ViewIdPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ViewIdPB create() => ViewIdPB._();
  ViewIdPB createEmptyInstance() => create();
  static $pb.PbList<ViewIdPB> createRepeated() => $pb.PbList<ViewIdPB>();
  @$core.pragma('dart2js:noInline')
  static ViewIdPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ViewIdPB>(create);
  static ViewIdPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get value => $_getSZ(0);
  @$pb.TagNumber(1)
  set value($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => clearField(1);
}

class SetPublishNamePB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SetPublishNamePB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'newName')
    ..hasRequiredFields = false
  ;

  SetPublishNamePB._() : super();
  factory SetPublishNamePB({
    $core.String? viewId,
    $core.String? newName,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (newName != null) {
      _result.newName = newName;
    }
    return _result;
  }
  factory SetPublishNamePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SetPublishNamePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SetPublishNamePB clone() => SetPublishNamePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SetPublishNamePB copyWith(void Function(SetPublishNamePB) updates) => super.copyWith((message) => updates(message as SetPublishNamePB)) as SetPublishNamePB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SetPublishNamePB create() => SetPublishNamePB._();
  SetPublishNamePB createEmptyInstance() => create();
  static $pb.PbList<SetPublishNamePB> createRepeated() => $pb.PbList<SetPublishNamePB>();
  @$core.pragma('dart2js:noInline')
  static SetPublishNamePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetPublishNamePB>(create);
  static SetPublishNamePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get newName => $_getSZ(1);
  @$pb.TagNumber(2)
  set newName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewName() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewName() => clearField(2);
}

enum DeletedViewPB_OneOfIndex {
  index_, 
  notSet
}

class DeletedViewPB extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, DeletedViewPB_OneOfIndex> _DeletedViewPB_OneOfIndexByTag = {
    2 : DeletedViewPB_OneOfIndex.index_,
    0 : DeletedViewPB_OneOfIndex.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DeletedViewPB', createEmptyInstance: create)
    ..oo(0, [2])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'index', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  DeletedViewPB._() : super();
  factory DeletedViewPB({
    $core.String? viewId,
    $core.int? index,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (index != null) {
      _result.index = index;
    }
    return _result;
  }
  factory DeletedViewPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeletedViewPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeletedViewPB clone() => DeletedViewPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeletedViewPB copyWith(void Function(DeletedViewPB) updates) => super.copyWith((message) => updates(message as DeletedViewPB)) as DeletedViewPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DeletedViewPB create() => DeletedViewPB._();
  DeletedViewPB createEmptyInstance() => create();
  static $pb.PbList<DeletedViewPB> createRepeated() => $pb.PbList<DeletedViewPB>();
  @$core.pragma('dart2js:noInline')
  static DeletedViewPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeletedViewPB>(create);
  static DeletedViewPB? _defaultInstance;

  DeletedViewPB_OneOfIndex whichOneOfIndex() => _DeletedViewPB_OneOfIndexByTag[$_whichOneof(0)]!;
  void clearOneOfIndex() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get index => $_getIZ(1);
  @$pb.TagNumber(2)
  set index($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndex() => clearField(2);
}

enum UpdateViewPayloadPB_OneOfName {
  name, 
  notSet
}

enum UpdateViewPayloadPB_OneOfDesc {
  desc, 
  notSet
}

enum UpdateViewPayloadPB_OneOfThumbnail {
  thumbnail, 
  notSet
}

enum UpdateViewPayloadPB_OneOfLayout {
  layout, 
  notSet
}

enum UpdateViewPayloadPB_OneOfIsFavorite {
  isFavorite, 
  notSet
}

enum UpdateViewPayloadPB_OneOfExtra {
  extra, 
  notSet
}

class UpdateViewPayloadPB extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfName> _UpdateViewPayloadPB_OneOfNameByTag = {
    2 : UpdateViewPayloadPB_OneOfName.name,
    0 : UpdateViewPayloadPB_OneOfName.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfDesc> _UpdateViewPayloadPB_OneOfDescByTag = {
    3 : UpdateViewPayloadPB_OneOfDesc.desc,
    0 : UpdateViewPayloadPB_OneOfDesc.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfThumbnail> _UpdateViewPayloadPB_OneOfThumbnailByTag = {
    4 : UpdateViewPayloadPB_OneOfThumbnail.thumbnail,
    0 : UpdateViewPayloadPB_OneOfThumbnail.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfLayout> _UpdateViewPayloadPB_OneOfLayoutByTag = {
    5 : UpdateViewPayloadPB_OneOfLayout.layout,
    0 : UpdateViewPayloadPB_OneOfLayout.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfIsFavorite> _UpdateViewPayloadPB_OneOfIsFavoriteByTag = {
    6 : UpdateViewPayloadPB_OneOfIsFavorite.isFavorite,
    0 : UpdateViewPayloadPB_OneOfIsFavorite.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfExtra> _UpdateViewPayloadPB_OneOfExtraByTag = {
    7 : UpdateViewPayloadPB_OneOfExtra.extra,
    0 : UpdateViewPayloadPB_OneOfExtra.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'UpdateViewPayloadPB', createEmptyInstance: create)
    ..oo(0, [2])
    ..oo(1, [3])
    ..oo(2, [4])
    ..oo(3, [5])
    ..oo(4, [6])
    ..oo(5, [7])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'desc')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thumbnail')
    ..e<ViewLayoutPB>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'layout', $pb.PbFieldType.OE, defaultOrMaker: ViewLayoutPB.Document, valueOf: ViewLayoutPB.valueOf, enumValues: ViewLayoutPB.values)
    ..aOB(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isFavorite')
    ..aOS(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'extra')
    ..hasRequiredFields = false
  ;

  UpdateViewPayloadPB._() : super();
  factory UpdateViewPayloadPB({
    $core.String? viewId,
    $core.String? name,
    $core.String? desc,
    $core.String? thumbnail,
    ViewLayoutPB? layout,
    $core.bool? isFavorite,
    $core.String? extra,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (name != null) {
      _result.name = name;
    }
    if (desc != null) {
      _result.desc = desc;
    }
    if (thumbnail != null) {
      _result.thumbnail = thumbnail;
    }
    if (layout != null) {
      _result.layout = layout;
    }
    if (isFavorite != null) {
      _result.isFavorite = isFavorite;
    }
    if (extra != null) {
      _result.extra = extra;
    }
    return _result;
  }
  factory UpdateViewPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UpdateViewPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UpdateViewPayloadPB clone() => UpdateViewPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UpdateViewPayloadPB copyWith(void Function(UpdateViewPayloadPB) updates) => super.copyWith((message) => updates(message as UpdateViewPayloadPB)) as UpdateViewPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static UpdateViewPayloadPB create() => UpdateViewPayloadPB._();
  UpdateViewPayloadPB createEmptyInstance() => create();
  static $pb.PbList<UpdateViewPayloadPB> createRepeated() => $pb.PbList<UpdateViewPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static UpdateViewPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UpdateViewPayloadPB>(create);
  static UpdateViewPayloadPB? _defaultInstance;

  UpdateViewPayloadPB_OneOfName whichOneOfName() => _UpdateViewPayloadPB_OneOfNameByTag[$_whichOneof(0)]!;
  void clearOneOfName() => clearField($_whichOneof(0));

  UpdateViewPayloadPB_OneOfDesc whichOneOfDesc() => _UpdateViewPayloadPB_OneOfDescByTag[$_whichOneof(1)]!;
  void clearOneOfDesc() => clearField($_whichOneof(1));

  UpdateViewPayloadPB_OneOfThumbnail whichOneOfThumbnail() => _UpdateViewPayloadPB_OneOfThumbnailByTag[$_whichOneof(2)]!;
  void clearOneOfThumbnail() => clearField($_whichOneof(2));

  UpdateViewPayloadPB_OneOfLayout whichOneOfLayout() => _UpdateViewPayloadPB_OneOfLayoutByTag[$_whichOneof(3)]!;
  void clearOneOfLayout() => clearField($_whichOneof(3));

  UpdateViewPayloadPB_OneOfIsFavorite whichOneOfIsFavorite() => _UpdateViewPayloadPB_OneOfIsFavoriteByTag[$_whichOneof(4)]!;
  void clearOneOfIsFavorite() => clearField($_whichOneof(4));

  UpdateViewPayloadPB_OneOfExtra whichOneOfExtra() => _UpdateViewPayloadPB_OneOfExtraByTag[$_whichOneof(5)]!;
  void clearOneOfExtra() => clearField($_whichOneof(5));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get desc => $_getSZ(2);
  @$pb.TagNumber(3)
  set desc($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDesc() => $_has(2);
  @$pb.TagNumber(3)
  void clearDesc() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get thumbnail => $_getSZ(3);
  @$pb.TagNumber(4)
  set thumbnail($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasThumbnail() => $_has(3);
  @$pb.TagNumber(4)
  void clearThumbnail() => clearField(4);

  @$pb.TagNumber(5)
  ViewLayoutPB get layout => $_getN(4);
  @$pb.TagNumber(5)
  set layout(ViewLayoutPB v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasLayout() => $_has(4);
  @$pb.TagNumber(5)
  void clearLayout() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isFavorite => $_getBF(5);
  @$pb.TagNumber(6)
  set isFavorite($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIsFavorite() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsFavorite() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get extra => $_getSZ(6);
  @$pb.TagNumber(7)
  set extra($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasExtra() => $_has(6);
  @$pb.TagNumber(7)
  void clearExtra() => clearField(7);
}

class MoveViewPayloadPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'MoveViewPayloadPB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'from', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'to', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  MoveViewPayloadPB._() : super();
  factory MoveViewPayloadPB({
    $core.String? viewId,
    $core.int? from,
    $core.int? to,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (from != null) {
      _result.from = from;
    }
    if (to != null) {
      _result.to = to;
    }
    return _result;
  }
  factory MoveViewPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MoveViewPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MoveViewPayloadPB clone() => MoveViewPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MoveViewPayloadPB copyWith(void Function(MoveViewPayloadPB) updates) => super.copyWith((message) => updates(message as MoveViewPayloadPB)) as MoveViewPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static MoveViewPayloadPB create() => MoveViewPayloadPB._();
  MoveViewPayloadPB createEmptyInstance() => create();
  static $pb.PbList<MoveViewPayloadPB> createRepeated() => $pb.PbList<MoveViewPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static MoveViewPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MoveViewPayloadPB>(create);
  static MoveViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get from => $_getIZ(1);
  @$pb.TagNumber(2)
  set from($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFrom() => $_has(1);
  @$pb.TagNumber(2)
  void clearFrom() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get to => $_getIZ(2);
  @$pb.TagNumber(3)
  set to($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTo() => $_has(2);
  @$pb.TagNumber(3)
  void clearTo() => clearField(3);
}

enum MoveNestedViewPayloadPB_OneOfPrevViewId {
  prevViewId, 
  notSet
}

enum MoveNestedViewPayloadPB_OneOfFromSection {
  fromSection, 
  notSet
}

enum MoveNestedViewPayloadPB_OneOfToSection {
  toSection, 
  notSet
}

class MoveNestedViewPayloadPB extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, MoveNestedViewPayloadPB_OneOfPrevViewId> _MoveNestedViewPayloadPB_OneOfPrevViewIdByTag = {
    3 : MoveNestedViewPayloadPB_OneOfPrevViewId.prevViewId,
    0 : MoveNestedViewPayloadPB_OneOfPrevViewId.notSet
  };
  static const $core.Map<$core.int, MoveNestedViewPayloadPB_OneOfFromSection> _MoveNestedViewPayloadPB_OneOfFromSectionByTag = {
    4 : MoveNestedViewPayloadPB_OneOfFromSection.fromSection,
    0 : MoveNestedViewPayloadPB_OneOfFromSection.notSet
  };
  static const $core.Map<$core.int, MoveNestedViewPayloadPB_OneOfToSection> _MoveNestedViewPayloadPB_OneOfToSectionByTag = {
    5 : MoveNestedViewPayloadPB_OneOfToSection.toSection,
    0 : MoveNestedViewPayloadPB_OneOfToSection.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'MoveNestedViewPayloadPB', createEmptyInstance: create)
    ..oo(0, [3])
    ..oo(1, [4])
    ..oo(2, [5])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'newParentId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'prevViewId')
    ..e<ViewSectionPB>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'fromSection', $pb.PbFieldType.OE, defaultOrMaker: ViewSectionPB.Private, valueOf: ViewSectionPB.valueOf, enumValues: ViewSectionPB.values)
    ..e<ViewSectionPB>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'toSection', $pb.PbFieldType.OE, defaultOrMaker: ViewSectionPB.Private, valueOf: ViewSectionPB.valueOf, enumValues: ViewSectionPB.values)
    ..hasRequiredFields = false
  ;

  MoveNestedViewPayloadPB._() : super();
  factory MoveNestedViewPayloadPB({
    $core.String? viewId,
    $core.String? newParentId,
    $core.String? prevViewId,
    ViewSectionPB? fromSection,
    ViewSectionPB? toSection,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (newParentId != null) {
      _result.newParentId = newParentId;
    }
    if (prevViewId != null) {
      _result.prevViewId = prevViewId;
    }
    if (fromSection != null) {
      _result.fromSection = fromSection;
    }
    if (toSection != null) {
      _result.toSection = toSection;
    }
    return _result;
  }
  factory MoveNestedViewPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MoveNestedViewPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MoveNestedViewPayloadPB clone() => MoveNestedViewPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MoveNestedViewPayloadPB copyWith(void Function(MoveNestedViewPayloadPB) updates) => super.copyWith((message) => updates(message as MoveNestedViewPayloadPB)) as MoveNestedViewPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static MoveNestedViewPayloadPB create() => MoveNestedViewPayloadPB._();
  MoveNestedViewPayloadPB createEmptyInstance() => create();
  static $pb.PbList<MoveNestedViewPayloadPB> createRepeated() => $pb.PbList<MoveNestedViewPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static MoveNestedViewPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MoveNestedViewPayloadPB>(create);
  static MoveNestedViewPayloadPB? _defaultInstance;

  MoveNestedViewPayloadPB_OneOfPrevViewId whichOneOfPrevViewId() => _MoveNestedViewPayloadPB_OneOfPrevViewIdByTag[$_whichOneof(0)]!;
  void clearOneOfPrevViewId() => clearField($_whichOneof(0));

  MoveNestedViewPayloadPB_OneOfFromSection whichOneOfFromSection() => _MoveNestedViewPayloadPB_OneOfFromSectionByTag[$_whichOneof(1)]!;
  void clearOneOfFromSection() => clearField($_whichOneof(1));

  MoveNestedViewPayloadPB_OneOfToSection whichOneOfToSection() => _MoveNestedViewPayloadPB_OneOfToSectionByTag[$_whichOneof(2)]!;
  void clearOneOfToSection() => clearField($_whichOneof(2));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get newParentId => $_getSZ(1);
  @$pb.TagNumber(2)
  set newParentId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNewParentId() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewParentId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get prevViewId => $_getSZ(2);
  @$pb.TagNumber(3)
  set prevViewId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPrevViewId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPrevViewId() => clearField(3);

  @$pb.TagNumber(4)
  ViewSectionPB get fromSection => $_getN(3);
  @$pb.TagNumber(4)
  set fromSection(ViewSectionPB v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasFromSection() => $_has(3);
  @$pb.TagNumber(4)
  void clearFromSection() => clearField(4);

  @$pb.TagNumber(5)
  ViewSectionPB get toSection => $_getN(4);
  @$pb.TagNumber(5)
  set toSection(ViewSectionPB v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasToSection() => $_has(4);
  @$pb.TagNumber(5)
  void clearToSection() => clearField(5);
}

class UpdateRecentViewPayloadPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'UpdateRecentViewPayloadPB', createEmptyInstance: create)
    ..pPS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewIds')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'addInRecent')
    ..hasRequiredFields = false
  ;

  UpdateRecentViewPayloadPB._() : super();
  factory UpdateRecentViewPayloadPB({
    $core.Iterable<$core.String>? viewIds,
    $core.bool? addInRecent,
  }) {
    final _result = create();
    if (viewIds != null) {
      _result.viewIds.addAll(viewIds);
    }
    if (addInRecent != null) {
      _result.addInRecent = addInRecent;
    }
    return _result;
  }
  factory UpdateRecentViewPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UpdateRecentViewPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UpdateRecentViewPayloadPB clone() => UpdateRecentViewPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UpdateRecentViewPayloadPB copyWith(void Function(UpdateRecentViewPayloadPB) updates) => super.copyWith((message) => updates(message as UpdateRecentViewPayloadPB)) as UpdateRecentViewPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static UpdateRecentViewPayloadPB create() => UpdateRecentViewPayloadPB._();
  UpdateRecentViewPayloadPB createEmptyInstance() => create();
  static $pb.PbList<UpdateRecentViewPayloadPB> createRepeated() => $pb.PbList<UpdateRecentViewPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static UpdateRecentViewPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UpdateRecentViewPayloadPB>(create);
  static UpdateRecentViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get viewIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get addInRecent => $_getBF(1);
  @$pb.TagNumber(2)
  set addInRecent($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAddInRecent() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddInRecent() => clearField(2);
}

class UpdateViewVisibilityStatusPayloadPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'UpdateViewVisibilityStatusPayloadPB', createEmptyInstance: create)
    ..pPS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewIds')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isPublic')
    ..hasRequiredFields = false
  ;

  UpdateViewVisibilityStatusPayloadPB._() : super();
  factory UpdateViewVisibilityStatusPayloadPB({
    $core.Iterable<$core.String>? viewIds,
    $core.bool? isPublic,
  }) {
    final _result = create();
    if (viewIds != null) {
      _result.viewIds.addAll(viewIds);
    }
    if (isPublic != null) {
      _result.isPublic = isPublic;
    }
    return _result;
  }
  factory UpdateViewVisibilityStatusPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UpdateViewVisibilityStatusPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UpdateViewVisibilityStatusPayloadPB clone() => UpdateViewVisibilityStatusPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UpdateViewVisibilityStatusPayloadPB copyWith(void Function(UpdateViewVisibilityStatusPayloadPB) updates) => super.copyWith((message) => updates(message as UpdateViewVisibilityStatusPayloadPB)) as UpdateViewVisibilityStatusPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static UpdateViewVisibilityStatusPayloadPB create() => UpdateViewVisibilityStatusPayloadPB._();
  UpdateViewVisibilityStatusPayloadPB createEmptyInstance() => create();
  static $pb.PbList<UpdateViewVisibilityStatusPayloadPB> createRepeated() => $pb.PbList<UpdateViewVisibilityStatusPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static UpdateViewVisibilityStatusPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UpdateViewVisibilityStatusPayloadPB>(create);
  static UpdateViewVisibilityStatusPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get viewIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get isPublic => $_getBF(1);
  @$pb.TagNumber(2)
  set isPublic($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsPublic() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsPublic() => clearField(2);
}

enum DuplicateViewPayloadPB_OneOfParentViewId {
  parentViewId, 
  notSet
}

enum DuplicateViewPayloadPB_OneOfSuffix {
  suffix, 
  notSet
}

class DuplicateViewPayloadPB extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, DuplicateViewPayloadPB_OneOfParentViewId> _DuplicateViewPayloadPB_OneOfParentViewIdByTag = {
    4 : DuplicateViewPayloadPB_OneOfParentViewId.parentViewId,
    0 : DuplicateViewPayloadPB_OneOfParentViewId.notSet
  };
  static const $core.Map<$core.int, DuplicateViewPayloadPB_OneOfSuffix> _DuplicateViewPayloadPB_OneOfSuffixByTag = {
    5 : DuplicateViewPayloadPB_OneOfSuffix.suffix,
    0 : DuplicateViewPayloadPB_OneOfSuffix.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DuplicateViewPayloadPB', createEmptyInstance: create)
    ..oo(0, [4])
    ..oo(1, [5])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'openAfterDuplicate')
    ..aOB(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'includeChildren')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'parentViewId')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'suffix')
    ..aOB(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'syncAfterCreate')
    ..hasRequiredFields = false
  ;

  DuplicateViewPayloadPB._() : super();
  factory DuplicateViewPayloadPB({
    $core.String? viewId,
    $core.bool? openAfterDuplicate,
    $core.bool? includeChildren,
    $core.String? parentViewId,
    $core.String? suffix,
    $core.bool? syncAfterCreate,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (openAfterDuplicate != null) {
      _result.openAfterDuplicate = openAfterDuplicate;
    }
    if (includeChildren != null) {
      _result.includeChildren = includeChildren;
    }
    if (parentViewId != null) {
      _result.parentViewId = parentViewId;
    }
    if (suffix != null) {
      _result.suffix = suffix;
    }
    if (syncAfterCreate != null) {
      _result.syncAfterCreate = syncAfterCreate;
    }
    return _result;
  }
  factory DuplicateViewPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DuplicateViewPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DuplicateViewPayloadPB clone() => DuplicateViewPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DuplicateViewPayloadPB copyWith(void Function(DuplicateViewPayloadPB) updates) => super.copyWith((message) => updates(message as DuplicateViewPayloadPB)) as DuplicateViewPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static DuplicateViewPayloadPB create() => DuplicateViewPayloadPB._();
  DuplicateViewPayloadPB createEmptyInstance() => create();
  static $pb.PbList<DuplicateViewPayloadPB> createRepeated() => $pb.PbList<DuplicateViewPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static DuplicateViewPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DuplicateViewPayloadPB>(create);
  static DuplicateViewPayloadPB? _defaultInstance;

  DuplicateViewPayloadPB_OneOfParentViewId whichOneOfParentViewId() => _DuplicateViewPayloadPB_OneOfParentViewIdByTag[$_whichOneof(0)]!;
  void clearOneOfParentViewId() => clearField($_whichOneof(0));

  DuplicateViewPayloadPB_OneOfSuffix whichOneOfSuffix() => _DuplicateViewPayloadPB_OneOfSuffixByTag[$_whichOneof(1)]!;
  void clearOneOfSuffix() => clearField($_whichOneof(1));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get openAfterDuplicate => $_getBF(1);
  @$pb.TagNumber(2)
  set openAfterDuplicate($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOpenAfterDuplicate() => $_has(1);
  @$pb.TagNumber(2)
  void clearOpenAfterDuplicate() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get includeChildren => $_getBF(2);
  @$pb.TagNumber(3)
  set includeChildren($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIncludeChildren() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncludeChildren() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get parentViewId => $_getSZ(3);
  @$pb.TagNumber(4)
  set parentViewId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasParentViewId() => $_has(3);
  @$pb.TagNumber(4)
  void clearParentViewId() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get suffix => $_getSZ(4);
  @$pb.TagNumber(5)
  set suffix($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSuffix() => $_has(4);
  @$pb.TagNumber(5)
  void clearSuffix() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get syncAfterCreate => $_getBF(5);
  @$pb.TagNumber(6)
  set syncAfterCreate($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSyncAfterCreate() => $_has(5);
  @$pb.TagNumber(6)
  void clearSyncAfterCreate() => clearField(6);
}

class SharePageWithUserPayloadPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SharePageWithUserPayloadPB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..pPS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'emails')
    ..e<AFAccessLevelPB>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'accessLevel', $pb.PbFieldType.OE, defaultOrMaker: AFAccessLevelPB.ReadOnly, valueOf: AFAccessLevelPB.valueOf, enumValues: AFAccessLevelPB.values)
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'autoConfirm')
    ..hasRequiredFields = false
  ;

  SharePageWithUserPayloadPB._() : super();
  factory SharePageWithUserPayloadPB({
    $core.String? viewId,
    $core.Iterable<$core.String>? emails,
    AFAccessLevelPB? accessLevel,
    $core.bool? autoConfirm,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (emails != null) {
      _result.emails.addAll(emails);
    }
    if (accessLevel != null) {
      _result.accessLevel = accessLevel;
    }
    if (autoConfirm != null) {
      _result.autoConfirm = autoConfirm;
    }
    return _result;
  }
  factory SharePageWithUserPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SharePageWithUserPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SharePageWithUserPayloadPB clone() => SharePageWithUserPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SharePageWithUserPayloadPB copyWith(void Function(SharePageWithUserPayloadPB) updates) => super.copyWith((message) => updates(message as SharePageWithUserPayloadPB)) as SharePageWithUserPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SharePageWithUserPayloadPB create() => SharePageWithUserPayloadPB._();
  SharePageWithUserPayloadPB createEmptyInstance() => create();
  static $pb.PbList<SharePageWithUserPayloadPB> createRepeated() => $pb.PbList<SharePageWithUserPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static SharePageWithUserPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SharePageWithUserPayloadPB>(create);
  static SharePageWithUserPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get emails => $_getList(1);

  @$pb.TagNumber(3)
  AFAccessLevelPB get accessLevel => $_getN(2);
  @$pb.TagNumber(3)
  set accessLevel(AFAccessLevelPB v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasAccessLevel() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccessLevel() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get autoConfirm => $_getBF(3);
  @$pb.TagNumber(4)
  set autoConfirm($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAutoConfirm() => $_has(3);
  @$pb.TagNumber(4)
  void clearAutoConfirm() => clearField(4);
}

class RemoveUserFromSharedPagePayloadPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RemoveUserFromSharedPagePayloadPB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..pPS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'emails')
    ..hasRequiredFields = false
  ;

  RemoveUserFromSharedPagePayloadPB._() : super();
  factory RemoveUserFromSharedPagePayloadPB({
    $core.String? viewId,
    $core.Iterable<$core.String>? emails,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (emails != null) {
      _result.emails.addAll(emails);
    }
    return _result;
  }
  factory RemoveUserFromSharedPagePayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RemoveUserFromSharedPagePayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RemoveUserFromSharedPagePayloadPB clone() => RemoveUserFromSharedPagePayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RemoveUserFromSharedPagePayloadPB copyWith(void Function(RemoveUserFromSharedPagePayloadPB) updates) => super.copyWith((message) => updates(message as RemoveUserFromSharedPagePayloadPB)) as RemoveUserFromSharedPagePayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RemoveUserFromSharedPagePayloadPB create() => RemoveUserFromSharedPagePayloadPB._();
  RemoveUserFromSharedPagePayloadPB createEmptyInstance() => create();
  static $pb.PbList<RemoveUserFromSharedPagePayloadPB> createRepeated() => $pb.PbList<RemoveUserFromSharedPagePayloadPB>();
  @$core.pragma('dart2js:noInline')
  static RemoveUserFromSharedPagePayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RemoveUserFromSharedPagePayloadPB>(create);
  static RemoveUserFromSharedPagePayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get emails => $_getList(1);
}

enum SharedUserPB_OneOfAvatarUrl {
  avatarUrl,
  notSet
}

enum SharedUserPB_OneOfUserId {
  userId,
  notSet
}

class SharedUserPB extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, SharedUserPB_OneOfAvatarUrl> _SharedUserPB_OneOfAvatarUrlByTag = {
    5 : SharedUserPB_OneOfAvatarUrl.avatarUrl,
    0 : SharedUserPB_OneOfAvatarUrl.notSet
  };
  static const $core.Map<$core.int, SharedUserPB_OneOfUserId> _SharedUserPB_OneOfUserIdByTag = {
    6 : SharedUserPB_OneOfUserId.userId,
    0 : SharedUserPB_OneOfUserId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SharedUserPB', createEmptyInstance: create)
    ..oo(0, [5])
    ..oo(1, [6])
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'email')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..e<AFRolePB>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'role', $pb.PbFieldType.OE, defaultOrMaker: AFRolePB.Owner, valueOf: AFRolePB.valueOf, enumValues: AFRolePB.values)
    ..e<AFAccessLevelPB>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'accessLevel', $pb.PbFieldType.OE, defaultOrMaker: AFAccessLevelPB.ReadOnly, valueOf: AFAccessLevelPB.valueOf, enumValues: AFAccessLevelPB.values)
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'avatarUrl')
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  SharedUserPB._() : super();
  factory SharedUserPB({
    $core.String? email,
    $core.String? name,
    AFRolePB? role,
    AFAccessLevelPB? accessLevel,
    $core.String? avatarUrl,
    $core.String? userId,
  }) {
    final _result = create();
    if (email != null) {
      _result.email = email;
    }
    if (name != null) {
      _result.name = name;
    }
    if (role != null) {
      _result.role = role;
    }
    if (accessLevel != null) {
      _result.accessLevel = accessLevel;
    }
    if (avatarUrl != null) {
      _result.avatarUrl = avatarUrl;
    }
    if (userId != null) {
      _result.userId = userId;
    }
    return _result;
  }
  factory SharedUserPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SharedUserPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SharedUserPB clone() => SharedUserPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SharedUserPB copyWith(void Function(SharedUserPB) updates) => super.copyWith((message) => updates(message as SharedUserPB)) as SharedUserPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SharedUserPB create() => SharedUserPB._();
  SharedUserPB createEmptyInstance() => create();
  static $pb.PbList<SharedUserPB> createRepeated() => $pb.PbList<SharedUserPB>();
  @$core.pragma('dart2js:noInline')
  static SharedUserPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SharedUserPB>(create);
  static SharedUserPB? _defaultInstance;

  SharedUserPB_OneOfAvatarUrl whichOneOfAvatarUrl() => _SharedUserPB_OneOfAvatarUrlByTag[$_whichOneof(0)]!;
  void clearOneOfAvatarUrl() => clearField($_whichOneof(0));

  SharedUserPB_OneOfUserId whichOneOfUserId() => _SharedUserPB_OneOfUserIdByTag[$_whichOneof(1)]!;
  void clearOneOfUserId() => clearField($_whichOneof(1));

  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  AFRolePB get role => $_getN(2);
  @$pb.TagNumber(3)
  set role(AFRolePB v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => clearField(3);

  @$pb.TagNumber(4)
  AFAccessLevelPB get accessLevel => $_getN(3);
  @$pb.TagNumber(4)
  set accessLevel(AFAccessLevelPB v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasAccessLevel() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccessLevel() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get avatarUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set avatarUrl($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAvatarUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvatarUrl() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get userId => $_getSZ(5);
  @$pb.TagNumber(6)
  set userId($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasUserId() => $_has(5);
  @$pb.TagNumber(6)
  void clearUserId() => clearField(6);
}

class RepeatedSharedUserPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RepeatedSharedUserPB', createEmptyInstance: create)
    ..pc<SharedUserPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'items', $pb.PbFieldType.PM, subBuilder: SharedUserPB.create)
    ..hasRequiredFields = false
  ;

  RepeatedSharedUserPB._() : super();
  factory RepeatedSharedUserPB({
    $core.Iterable<SharedUserPB>? items,
  }) {
    final _result = create();
    if (items != null) {
      _result.items.addAll(items);
    }
    return _result;
  }
  factory RepeatedSharedUserPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedSharedUserPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedSharedUserPB clone() => RepeatedSharedUserPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedSharedUserPB copyWith(void Function(RepeatedSharedUserPB) updates) => super.copyWith((message) => updates(message as RepeatedSharedUserPB)) as RepeatedSharedUserPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RepeatedSharedUserPB create() => RepeatedSharedUserPB._();
  RepeatedSharedUserPB createEmptyInstance() => create();
  static $pb.PbList<RepeatedSharedUserPB> createRepeated() => $pb.PbList<RepeatedSharedUserPB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedSharedUserPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedSharedUserPB>(create);
  static RepeatedSharedUserPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<SharedUserPB> get items => $_getList(0);
}

class GetSharedUsersPayloadPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'GetSharedUsersPayloadPB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..hasRequiredFields = false
  ;

  GetSharedUsersPayloadPB._() : super();
  factory GetSharedUsersPayloadPB({
    $core.String? viewId,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    return _result;
  }
  factory GetSharedUsersPayloadPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetSharedUsersPayloadPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetSharedUsersPayloadPB clone() => GetSharedUsersPayloadPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetSharedUsersPayloadPB copyWith(void Function(GetSharedUsersPayloadPB) updates) => super.copyWith((message) => updates(message as GetSharedUsersPayloadPB)) as GetSharedUsersPayloadPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static GetSharedUsersPayloadPB create() => GetSharedUsersPayloadPB._();
  GetSharedUsersPayloadPB createEmptyInstance() => create();
  static $pb.PbList<GetSharedUsersPayloadPB> createRepeated() => $pb.PbList<GetSharedUsersPayloadPB>();
  @$core.pragma('dart2js:noInline')
  static GetSharedUsersPayloadPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetSharedUsersPayloadPB>(create);
  static GetSharedUsersPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);
}

enum SharedViewPB_OneOfWorkspaceId {
  workspaceId, 
  notSet
}

class SharedViewPB extends $pb.GeneratedMessage {
  static const $core.Map<$core.int, SharedViewPB_OneOfWorkspaceId> _SharedViewPB_OneOfWorkspaceIdByTag = {
    3 : SharedViewPB_OneOfWorkspaceId.workspaceId,
    0 : SharedViewPB_OneOfWorkspaceId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SharedViewPB', createEmptyInstance: create)
    ..oo(0, [3])
    ..aOM<ViewPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'view', subBuilder: ViewPB.create)
    ..e<AFAccessLevelPB>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'accessLevel', $pb.PbFieldType.OE, defaultOrMaker: AFAccessLevelPB.ReadOnly, valueOf: AFAccessLevelPB.valueOf, enumValues: AFAccessLevelPB.values)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'workspaceId')
    ..hasRequiredFields = false
  ;

  SharedViewPB._() : super();
  factory SharedViewPB({
    ViewPB? view,
    AFAccessLevelPB? accessLevel,
    $core.String? workspaceId,
  }) {
    final _result = create();
    if (view != null) {
      _result.view = view;
    }
    if (accessLevel != null) {
      _result.accessLevel = accessLevel;
    }
    if (workspaceId != null) {
      _result.workspaceId = workspaceId;
    }
    return _result;
  }
  factory SharedViewPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SharedViewPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SharedViewPB clone() => SharedViewPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SharedViewPB copyWith(void Function(SharedViewPB) updates) => super.copyWith((message) => updates(message as SharedViewPB)) as SharedViewPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SharedViewPB create() => SharedViewPB._();
  SharedViewPB createEmptyInstance() => create();
  static $pb.PbList<SharedViewPB> createRepeated() => $pb.PbList<SharedViewPB>();
  @$core.pragma('dart2js:noInline')
  static SharedViewPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SharedViewPB>(create);
  static SharedViewPB? _defaultInstance;

  SharedViewPB_OneOfWorkspaceId whichOneOfWorkspaceId() => _SharedViewPB_OneOfWorkspaceIdByTag[$_whichOneof(0)]!;
  void clearOneOfWorkspaceId() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ViewPB get view => $_getN(0);
  @$pb.TagNumber(1)
  set view(ViewPB v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasView() => $_has(0);
  @$pb.TagNumber(1)
  void clearView() => clearField(1);
  @$pb.TagNumber(1)
  ViewPB ensureView() => $_ensure(0);

  @$pb.TagNumber(2)
  AFAccessLevelPB get accessLevel => $_getN(1);
  @$pb.TagNumber(2)
  set accessLevel(AFAccessLevelPB v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccessLevel() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccessLevel() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get workspaceId => $_getSZ(2);
  @$pb.TagNumber(3)
  set workspaceId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasWorkspaceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearWorkspaceId() => clearField(3);
}

class RepeatedSharedViewResponsePB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'RepeatedSharedViewResponsePB', createEmptyInstance: create)
    ..pc<SharedViewPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sharedViews', $pb.PbFieldType.PM, subBuilder: SharedViewPB.create)
    ..hasRequiredFields = false
  ;

  RepeatedSharedViewResponsePB._() : super();
  factory RepeatedSharedViewResponsePB({
    $core.Iterable<SharedViewPB>? sharedViews,
  }) {
    final _result = create();
    if (sharedViews != null) {
      _result.sharedViews.addAll(sharedViews);
    }
    return _result;
  }
  factory RepeatedSharedViewResponsePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RepeatedSharedViewResponsePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RepeatedSharedViewResponsePB clone() => RepeatedSharedViewResponsePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RepeatedSharedViewResponsePB copyWith(void Function(RepeatedSharedViewResponsePB) updates) => super.copyWith((message) => updates(message as RepeatedSharedViewResponsePB)) as RepeatedSharedViewResponsePB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static RepeatedSharedViewResponsePB create() => RepeatedSharedViewResponsePB._();
  RepeatedSharedViewResponsePB createEmptyInstance() => create();
  static $pb.PbList<RepeatedSharedViewResponsePB> createRepeated() => $pb.PbList<RepeatedSharedViewResponsePB>();
  @$core.pragma('dart2js:noInline')
  static RepeatedSharedViewResponsePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RepeatedSharedViewResponsePB>(create);
  static RepeatedSharedViewResponsePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<SharedViewPB> get sharedViews => $_getList(0);
}

class GetSharedViewSectionResponsePB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'GetSharedViewSectionResponsePB', createEmptyInstance: create)
    ..e<SharedViewSectionPB>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'section', $pb.PbFieldType.OE, defaultOrMaker: SharedViewSectionPB.PrivateSection, valueOf: SharedViewSectionPB.valueOf, enumValues: SharedViewSectionPB.values)
    ..hasRequiredFields = false
  ;

  GetSharedViewSectionResponsePB._() : super();
  factory GetSharedViewSectionResponsePB({
    SharedViewSectionPB? section,
  }) {
    final _result = create();
    if (section != null) {
      _result.section = section;
    }
    return _result;
  }
  factory GetSharedViewSectionResponsePB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GetSharedViewSectionResponsePB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GetSharedViewSectionResponsePB clone() => GetSharedViewSectionResponsePB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GetSharedViewSectionResponsePB copyWith(void Function(GetSharedViewSectionResponsePB) updates) => super.copyWith((message) => updates(message as GetSharedViewSectionResponsePB)) as GetSharedViewSectionResponsePB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static GetSharedViewSectionResponsePB create() => GetSharedViewSectionResponsePB._();
  GetSharedViewSectionResponsePB createEmptyInstance() => create();
  static $pb.PbList<GetSharedViewSectionResponsePB> createRepeated() => $pb.PbList<GetSharedViewSectionResponsePB>();
  @$core.pragma('dart2js:noInline')
  static GetSharedViewSectionResponsePB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetSharedViewSectionResponsePB>(create);
  static GetSharedViewSectionResponsePB? _defaultInstance;

  @$pb.TagNumber(1)
  SharedViewSectionPB get section => $_getN(0);
  @$pb.TagNumber(1)
  set section(SharedViewSectionPB v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasSection() => $_has(0);
  @$pb.TagNumber(1)
  void clearSection() => clearField(1);
}

class SaveSharedViewMetaPB extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SaveSharedViewMetaPB', createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'workspaceId')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewName')
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'viewLayout', $pb.PbFieldType.O3)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'permissionId', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  SaveSharedViewMetaPB._() : super();
  factory SaveSharedViewMetaPB({
    $core.String? viewId,
    $core.String? workspaceId,
    $core.String? viewName,
    $core.int? viewLayout,
    $core.int? permissionId,
  }) {
    final _result = create();
    if (viewId != null) {
      _result.viewId = viewId;
    }
    if (workspaceId != null) {
      _result.workspaceId = workspaceId;
    }
    if (viewName != null) {
      _result.viewName = viewName;
    }
    if (viewLayout != null) {
      _result.viewLayout = viewLayout;
    }
    if (permissionId != null) {
      _result.permissionId = permissionId;
    }
    return _result;
  }
  factory SaveSharedViewMetaPB.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SaveSharedViewMetaPB.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SaveSharedViewMetaPB clone() => SaveSharedViewMetaPB()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SaveSharedViewMetaPB copyWith(void Function(SaveSharedViewMetaPB) updates) => super.copyWith((message) => updates(message as SaveSharedViewMetaPB)) as SaveSharedViewMetaPB; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SaveSharedViewMetaPB create() => SaveSharedViewMetaPB._();
  SaveSharedViewMetaPB createEmptyInstance() => create();
  static $pb.PbList<SaveSharedViewMetaPB> createRepeated() => $pb.PbList<SaveSharedViewMetaPB>();
  @$core.pragma('dart2js:noInline')
  static SaveSharedViewMetaPB getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SaveSharedViewMetaPB>(create);
  static SaveSharedViewMetaPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get workspaceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set workspaceId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasWorkspaceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearWorkspaceId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get viewName => $_getSZ(2);
  @$pb.TagNumber(3)
  set viewName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasViewName() => $_has(2);
  @$pb.TagNumber(3)
  void clearViewName() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get viewLayout => $_getIZ(3);
  @$pb.TagNumber(4)
  set viewLayout($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasViewLayout() => $_has(3);
  @$pb.TagNumber(4)
  void clearViewLayout() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get permissionId => $_getIZ(4);
  @$pb.TagNumber(5)
  set permissionId($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPermissionId() => $_has(4);
  @$pb.TagNumber(5)
  void clearPermissionId() => clearField(5);
}

