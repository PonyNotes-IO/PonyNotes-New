// This is a generated file - do not edit.
//
// Generated from view.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'icon.pb.dart' as $0;
import 'view.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'view.pbenum.dart';

class ChildViewUpdatePB extends $pb.GeneratedMessage {
  factory ChildViewUpdatePB({
    $core.String? parentViewId,
    $core.Iterable<ViewPB>? createChildViews,
    $core.Iterable<$core.String>? deleteChildViews,
    $core.Iterable<ViewPB>? updateChildViews,
  }) {
    final result = create();
    if (parentViewId != null) result.parentViewId = parentViewId;
    if (createChildViews != null)
      result.createChildViews.addAll(createChildViews);
    if (deleteChildViews != null)
      result.deleteChildViews.addAll(deleteChildViews);
    if (updateChildViews != null)
      result.updateChildViews.addAll(updateChildViews);
    return result;
  }

  ChildViewUpdatePB._();

  factory ChildViewUpdatePB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChildViewUpdatePB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChildViewUpdatePB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'parentViewId')
    ..pPM<ViewPB>(2, _omitFieldNames ? '' : 'createChildViews',
        subBuilder: ViewPB.create)
    ..pPS(3, _omitFieldNames ? '' : 'deleteChildViews')
    ..pPM<ViewPB>(4, _omitFieldNames ? '' : 'updateChildViews',
        subBuilder: ViewPB.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChildViewUpdatePB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChildViewUpdatePB copyWith(void Function(ChildViewUpdatePB) updates) =>
      super.copyWith((message) => updates(message as ChildViewUpdatePB))
          as ChildViewUpdatePB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChildViewUpdatePB create() => ChildViewUpdatePB._();
  @$core.override
  ChildViewUpdatePB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChildViewUpdatePB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChildViewUpdatePB>(create);
  static ChildViewUpdatePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get parentViewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set parentViewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasParentViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearParentViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ViewPB> get createChildViews => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get deleteChildViews => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<ViewPB> get updateChildViews => $_getList(3);
}

enum ViewPB_OneOfIcon { icon, notSet }

enum ViewPB_OneOfExtra { extra, notSet }

enum ViewPB_OneOfCreatedBy { createdBy, notSet }

enum ViewPB_OneOfLastEditedBy { lastEditedBy, notSet }

enum ViewPB_OneOfIsLocked { isLocked, notSet }

enum ViewPB_OneOfWorkspaceId { workspaceId, notSet }

class ViewPB extends $pb.GeneratedMessage {
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
    final result = create();
    if (id != null) result.id = id;
    if (parentViewId != null) result.parentViewId = parentViewId;
    if (name != null) result.name = name;
    if (createTime != null) result.createTime = createTime;
    if (childViews != null) result.childViews.addAll(childViews);
    if (layout != null) result.layout = layout;
    if (icon != null) result.icon = icon;
    if (isFavorite != null) result.isFavorite = isFavorite;
    if (extra != null) result.extra = extra;
    if (createdBy != null) result.createdBy = createdBy;
    if (lastEdited != null) result.lastEdited = lastEdited;
    if (lastEditedBy != null) result.lastEditedBy = lastEditedBy;
    if (isLocked != null) result.isLocked = isLocked;
    if (workspaceId != null) result.workspaceId = workspaceId;
    return result;
  }

  ViewPB._();

  factory ViewPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ViewPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ViewPB_OneOfIcon> _ViewPB_OneOfIconByTag = {
    7: ViewPB_OneOfIcon.icon,
    0: ViewPB_OneOfIcon.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfExtra> _ViewPB_OneOfExtraByTag =
      {9: ViewPB_OneOfExtra.extra, 0: ViewPB_OneOfExtra.notSet};
  static const $core.Map<$core.int, ViewPB_OneOfCreatedBy>
      _ViewPB_OneOfCreatedByByTag = {
    10: ViewPB_OneOfCreatedBy.createdBy,
    0: ViewPB_OneOfCreatedBy.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfLastEditedBy>
      _ViewPB_OneOfLastEditedByByTag = {
    12: ViewPB_OneOfLastEditedBy.lastEditedBy,
    0: ViewPB_OneOfLastEditedBy.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfIsLocked>
      _ViewPB_OneOfIsLockedByTag = {
    13: ViewPB_OneOfIsLocked.isLocked,
    0: ViewPB_OneOfIsLocked.notSet
  };
  static const $core.Map<$core.int, ViewPB_OneOfWorkspaceId>
      _ViewPB_OneOfWorkspaceIdByTag = {
    14: ViewPB_OneOfWorkspaceId.workspaceId,
    0: ViewPB_OneOfWorkspaceId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ViewPB',
      createEmptyInstance: create)
    ..oo(0, [7])
    ..oo(1, [9])
    ..oo(2, [10])
    ..oo(3, [12])
    ..oo(4, [13])
    ..oo(5, [14])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'parentViewId')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..aInt64(4, _omitFieldNames ? '' : 'createTime')
    ..pPM<ViewPB>(5, _omitFieldNames ? '' : 'childViews',
        subBuilder: ViewPB.create)
    ..aE<ViewLayoutPB>(6, _omitFieldNames ? '' : 'layout',
        enumValues: ViewLayoutPB.values)
    ..aOM<$0.ViewIconPB>(7, _omitFieldNames ? '' : 'icon',
        subBuilder: $0.ViewIconPB.create)
    ..aOB(8, _omitFieldNames ? '' : 'isFavorite')
    ..aOS(9, _omitFieldNames ? '' : 'extra')
    ..aInt64(10, _omitFieldNames ? '' : 'createdBy')
    ..aInt64(11, _omitFieldNames ? '' : 'lastEdited')
    ..aInt64(12, _omitFieldNames ? '' : 'lastEditedBy')
    ..aOB(13, _omitFieldNames ? '' : 'isLocked')
    ..aOS(14, _omitFieldNames ? '' : 'workspaceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ViewPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ViewPB copyWith(void Function(ViewPB) updates) =>
      super.copyWith((message) => updates(message as ViewPB)) as ViewPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ViewPB create() => ViewPB._();
  @$core.override
  ViewPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ViewPB getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ViewPB>(create);
  static ViewPB? _defaultInstance;

  @$pb.TagNumber(7)
  ViewPB_OneOfIcon whichOneOfIcon() => _ViewPB_OneOfIconByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(7)
  void clearOneOfIcon() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(9)
  ViewPB_OneOfExtra whichOneOfExtra() =>
      _ViewPB_OneOfExtraByTag[$_whichOneof(1)]!;
  @$pb.TagNumber(9)
  void clearOneOfExtra() => $_clearField($_whichOneof(1));

  @$pb.TagNumber(10)
  ViewPB_OneOfCreatedBy whichOneOfCreatedBy() =>
      _ViewPB_OneOfCreatedByByTag[$_whichOneof(2)]!;
  @$pb.TagNumber(10)
  void clearOneOfCreatedBy() => $_clearField($_whichOneof(2));

  @$pb.TagNumber(12)
  ViewPB_OneOfLastEditedBy whichOneOfLastEditedBy() =>
      _ViewPB_OneOfLastEditedByByTag[$_whichOneof(3)]!;
  @$pb.TagNumber(12)
  void clearOneOfLastEditedBy() => $_clearField($_whichOneof(3));

  @$pb.TagNumber(13)
  ViewPB_OneOfIsLocked whichOneOfIsLocked() =>
      _ViewPB_OneOfIsLockedByTag[$_whichOneof(4)]!;
  @$pb.TagNumber(13)
  void clearOneOfIsLocked() => $_clearField($_whichOneof(4));

  @$pb.TagNumber(14)
  ViewPB_OneOfWorkspaceId whichOneOfWorkspaceId() =>
      _ViewPB_OneOfWorkspaceIdByTag[$_whichOneof(5)]!;
  @$pb.TagNumber(14)
  void clearOneOfWorkspaceId() => $_clearField($_whichOneof(5));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get parentViewId => $_getSZ(1);
  @$pb.TagNumber(2)
  set parentViewId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasParentViewId() => $_has(1);
  @$pb.TagNumber(2)
  void clearParentViewId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get createTime => $_getI64(3);
  @$pb.TagNumber(4)
  set createTime($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCreateTime() => $_has(3);
  @$pb.TagNumber(4)
  void clearCreateTime() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<ViewPB> get childViews => $_getList(4);

  @$pb.TagNumber(6)
  ViewLayoutPB get layout => $_getN(5);
  @$pb.TagNumber(6)
  set layout(ViewLayoutPB value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasLayout() => $_has(5);
  @$pb.TagNumber(6)
  void clearLayout() => $_clearField(6);

  @$pb.TagNumber(7)
  $0.ViewIconPB get icon => $_getN(6);
  @$pb.TagNumber(7)
  set icon($0.ViewIconPB value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasIcon() => $_has(6);
  @$pb.TagNumber(7)
  void clearIcon() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.ViewIconPB ensureIcon() => $_ensure(6);

  @$pb.TagNumber(8)
  $core.bool get isFavorite => $_getBF(7);
  @$pb.TagNumber(8)
  set isFavorite($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasIsFavorite() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsFavorite() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get extra => $_getSZ(8);
  @$pb.TagNumber(9)
  set extra($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasExtra() => $_has(8);
  @$pb.TagNumber(9)
  void clearExtra() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get createdBy => $_getI64(9);
  @$pb.TagNumber(10)
  set createdBy($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCreatedBy() => $_has(9);
  @$pb.TagNumber(10)
  void clearCreatedBy() => $_clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get lastEdited => $_getI64(10);
  @$pb.TagNumber(11)
  set lastEdited($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLastEdited() => $_has(10);
  @$pb.TagNumber(11)
  void clearLastEdited() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get lastEditedBy => $_getI64(11);
  @$pb.TagNumber(12)
  set lastEditedBy($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasLastEditedBy() => $_has(11);
  @$pb.TagNumber(12)
  void clearLastEditedBy() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.bool get isLocked => $_getBF(12);
  @$pb.TagNumber(13)
  set isLocked($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasIsLocked() => $_has(12);
  @$pb.TagNumber(13)
  void clearIsLocked() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get workspaceId => $_getSZ(13);
  @$pb.TagNumber(14)
  set workspaceId($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasWorkspaceId() => $_has(13);
  @$pb.TagNumber(14)
  void clearWorkspaceId() => $_clearField(14);
}

class SectionViewsPB extends $pb.GeneratedMessage {
  factory SectionViewsPB({
    ViewSectionPB? section,
    $core.Iterable<ViewPB>? views,
  }) {
    final result = create();
    if (section != null) result.section = section;
    if (views != null) result.views.addAll(views);
    return result;
  }

  SectionViewsPB._();

  factory SectionViewsPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SectionViewsPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SectionViewsPB',
      createEmptyInstance: create)
    ..aE<ViewSectionPB>(1, _omitFieldNames ? '' : 'section',
        enumValues: ViewSectionPB.values)
    ..pPM<ViewPB>(2, _omitFieldNames ? '' : 'views', subBuilder: ViewPB.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SectionViewsPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SectionViewsPB copyWith(void Function(SectionViewsPB) updates) =>
      super.copyWith((message) => updates(message as SectionViewsPB))
          as SectionViewsPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SectionViewsPB create() => SectionViewsPB._();
  @$core.override
  SectionViewsPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SectionViewsPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SectionViewsPB>(create);
  static SectionViewsPB? _defaultInstance;

  @$pb.TagNumber(1)
  ViewSectionPB get section => $_getN(0);
  @$pb.TagNumber(1)
  set section(ViewSectionPB value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSection() => $_has(0);
  @$pb.TagNumber(1)
  void clearSection() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ViewPB> get views => $_getList(1);
}

class RepeatedViewPB extends $pb.GeneratedMessage {
  factory RepeatedViewPB({
    $core.Iterable<ViewPB>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  RepeatedViewPB._();

  factory RepeatedViewPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RepeatedViewPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RepeatedViewPB',
      createEmptyInstance: create)
    ..pPM<ViewPB>(1, _omitFieldNames ? '' : 'items', subBuilder: ViewPB.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedViewPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedViewPB copyWith(void Function(RepeatedViewPB) updates) =>
      super.copyWith((message) => updates(message as RepeatedViewPB))
          as RepeatedViewPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedViewPB create() => RepeatedViewPB._();
  @$core.override
  RepeatedViewPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RepeatedViewPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RepeatedViewPB>(create);
  static RepeatedViewPB? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ViewPB> get items => $_getList(0);
}

class RepeatedFavoriteViewPB extends $pb.GeneratedMessage {
  factory RepeatedFavoriteViewPB({
    $core.Iterable<SectionViewPB>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  RepeatedFavoriteViewPB._();

  factory RepeatedFavoriteViewPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RepeatedFavoriteViewPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RepeatedFavoriteViewPB',
      createEmptyInstance: create)
    ..pPM<SectionViewPB>(1, _omitFieldNames ? '' : 'items',
        subBuilder: SectionViewPB.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedFavoriteViewPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedFavoriteViewPB copyWith(
          void Function(RepeatedFavoriteViewPB) updates) =>
      super.copyWith((message) => updates(message as RepeatedFavoriteViewPB))
          as RepeatedFavoriteViewPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedFavoriteViewPB create() => RepeatedFavoriteViewPB._();
  @$core.override
  RepeatedFavoriteViewPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RepeatedFavoriteViewPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RepeatedFavoriteViewPB>(create);
  static RepeatedFavoriteViewPB? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SectionViewPB> get items => $_getList(0);
}

class ReadRecentViewsPB extends $pb.GeneratedMessage {
  factory ReadRecentViewsPB({
    $fixnum.Int64? start,
    $fixnum.Int64? limit,
  }) {
    final result = create();
    if (start != null) result.start = start;
    if (limit != null) result.limit = limit;
    return result;
  }

  ReadRecentViewsPB._();

  factory ReadRecentViewsPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReadRecentViewsPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadRecentViewsPB',
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'start', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadRecentViewsPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadRecentViewsPB copyWith(void Function(ReadRecentViewsPB) updates) =>
      super.copyWith((message) => updates(message as ReadRecentViewsPB))
          as ReadRecentViewsPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReadRecentViewsPB create() => ReadRecentViewsPB._();
  @$core.override
  ReadRecentViewsPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReadRecentViewsPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadRecentViewsPB>(create);
  static ReadRecentViewsPB? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get start => $_getI64(0);
  @$pb.TagNumber(1)
  set start($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearStart() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get limit => $_getI64(1);
  @$pb.TagNumber(2)
  set limit($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => $_clearField(2);
}

class RepeatedRecentViewPB extends $pb.GeneratedMessage {
  factory RepeatedRecentViewPB({
    $core.Iterable<SectionViewPB>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  RepeatedRecentViewPB._();

  factory RepeatedRecentViewPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RepeatedRecentViewPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RepeatedRecentViewPB',
      createEmptyInstance: create)
    ..pPM<SectionViewPB>(1, _omitFieldNames ? '' : 'items',
        subBuilder: SectionViewPB.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedRecentViewPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedRecentViewPB copyWith(void Function(RepeatedRecentViewPB) updates) =>
      super.copyWith((message) => updates(message as RepeatedRecentViewPB))
          as RepeatedRecentViewPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedRecentViewPB create() => RepeatedRecentViewPB._();
  @$core.override
  RepeatedRecentViewPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RepeatedRecentViewPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RepeatedRecentViewPB>(create);
  static RepeatedRecentViewPB? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SectionViewPB> get items => $_getList(0);
}

class SectionViewPB extends $pb.GeneratedMessage {
  factory SectionViewPB({
    ViewPB? item,
    $fixnum.Int64? timestamp,
  }) {
    final result = create();
    if (item != null) result.item = item;
    if (timestamp != null) result.timestamp = timestamp;
    return result;
  }

  SectionViewPB._();

  factory SectionViewPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SectionViewPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SectionViewPB',
      createEmptyInstance: create)
    ..aOM<ViewPB>(1, _omitFieldNames ? '' : 'item', subBuilder: ViewPB.create)
    ..aInt64(2, _omitFieldNames ? '' : 'timestamp')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SectionViewPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SectionViewPB copyWith(void Function(SectionViewPB) updates) =>
      super.copyWith((message) => updates(message as SectionViewPB))
          as SectionViewPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SectionViewPB create() => SectionViewPB._();
  @$core.override
  SectionViewPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SectionViewPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SectionViewPB>(create);
  static SectionViewPB? _defaultInstance;

  @$pb.TagNumber(1)
  ViewPB get item => $_getN(0);
  @$pb.TagNumber(1)
  set item(ViewPB value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasItem() => $_has(0);
  @$pb.TagNumber(1)
  void clearItem() => $_clearField(1);
  @$pb.TagNumber(1)
  ViewPB ensureItem() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => $_clearField(2);
}

class RepeatedViewIdPB extends $pb.GeneratedMessage {
  factory RepeatedViewIdPB({
    $core.Iterable<$core.String>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  RepeatedViewIdPB._();

  factory RepeatedViewIdPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RepeatedViewIdPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RepeatedViewIdPB',
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'items')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedViewIdPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedViewIdPB copyWith(void Function(RepeatedViewIdPB) updates) =>
      super.copyWith((message) => updates(message as RepeatedViewIdPB))
          as RepeatedViewIdPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedViewIdPB create() => RepeatedViewIdPB._();
  @$core.override
  RepeatedViewIdPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RepeatedViewIdPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RepeatedViewIdPB>(create);
  static RepeatedViewIdPB? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get items => $_getList(0);
}

enum CreateViewPayloadPB_OneOfThumbnail { thumbnail, notSet }

enum CreateViewPayloadPB_OneOfIndex { index_, notSet }

enum CreateViewPayloadPB_OneOfSection { section, notSet }

enum CreateViewPayloadPB_OneOfViewId { viewId, notSet }

enum CreateViewPayloadPB_OneOfExtra { extra, notSet }

class CreateViewPayloadPB extends $pb.GeneratedMessage {
  factory CreateViewPayloadPB({
    $core.String? parentViewId,
    $core.String? name,
    $core.String? thumbnail,
    ViewLayoutPB? layout,
    $core.List<$core.int>? initialData,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? meta,
    $core.bool? setAsCurrent,
    $core.int? index,
    ViewSectionPB? section,
    $core.String? viewId,
    $core.String? extra,
  }) {
    final result = create();
    if (parentViewId != null) result.parentViewId = parentViewId;
    if (name != null) result.name = name;
    if (thumbnail != null) result.thumbnail = thumbnail;
    if (layout != null) result.layout = layout;
    if (initialData != null) result.initialData = initialData;
    if (meta != null) result.meta.addEntries(meta);
    if (setAsCurrent != null) result.setAsCurrent = setAsCurrent;
    if (index != null) result.index = index;
    if (section != null) result.section = section;
    if (viewId != null) result.viewId = viewId;
    if (extra != null) result.extra = extra;
    return result;
  }

  CreateViewPayloadPB._();

  factory CreateViewPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateViewPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfThumbnail>
      _CreateViewPayloadPB_OneOfThumbnailByTag = {
    3: CreateViewPayloadPB_OneOfThumbnail.thumbnail,
    0: CreateViewPayloadPB_OneOfThumbnail.notSet
  };
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfIndex>
      _CreateViewPayloadPB_OneOfIndexByTag = {
    8: CreateViewPayloadPB_OneOfIndex.index_,
    0: CreateViewPayloadPB_OneOfIndex.notSet
  };
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfSection>
      _CreateViewPayloadPB_OneOfSectionByTag = {
    9: CreateViewPayloadPB_OneOfSection.section,
    0: CreateViewPayloadPB_OneOfSection.notSet
  };
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfViewId>
      _CreateViewPayloadPB_OneOfViewIdByTag = {
    10: CreateViewPayloadPB_OneOfViewId.viewId,
    0: CreateViewPayloadPB_OneOfViewId.notSet
  };
  static const $core.Map<$core.int, CreateViewPayloadPB_OneOfExtra>
      _CreateViewPayloadPB_OneOfExtraByTag = {
    11: CreateViewPayloadPB_OneOfExtra.extra,
    0: CreateViewPayloadPB_OneOfExtra.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateViewPayloadPB',
      createEmptyInstance: create)
    ..oo(0, [3])
    ..oo(1, [8])
    ..oo(2, [9])
    ..oo(3, [10])
    ..oo(4, [11])
    ..aOS(1, _omitFieldNames ? '' : 'parentViewId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'thumbnail')
    ..aE<ViewLayoutPB>(4, _omitFieldNames ? '' : 'layout',
        enumValues: ViewLayoutPB.values)
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'initialData', $pb.PbFieldType.OY)
    ..m<$core.String, $core.String>(6, _omitFieldNames ? '' : 'meta',
        entryClassName: 'CreateViewPayloadPB.MetaEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS)
    ..aOB(7, _omitFieldNames ? '' : 'setAsCurrent')
    ..aI(8, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aE<ViewSectionPB>(9, _omitFieldNames ? '' : 'section',
        enumValues: ViewSectionPB.values)
    ..aOS(10, _omitFieldNames ? '' : 'viewId')
    ..aOS(11, _omitFieldNames ? '' : 'extra')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateViewPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateViewPayloadPB copyWith(void Function(CreateViewPayloadPB) updates) =>
      super.copyWith((message) => updates(message as CreateViewPayloadPB))
          as CreateViewPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateViewPayloadPB create() => CreateViewPayloadPB._();
  @$core.override
  CreateViewPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateViewPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateViewPayloadPB>(create);
  static CreateViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(3)
  CreateViewPayloadPB_OneOfThumbnail whichOneOfThumbnail() =>
      _CreateViewPayloadPB_OneOfThumbnailByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  void clearOneOfThumbnail() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(8)
  CreateViewPayloadPB_OneOfIndex whichOneOfIndex() =>
      _CreateViewPayloadPB_OneOfIndexByTag[$_whichOneof(1)]!;
  @$pb.TagNumber(8)
  void clearOneOfIndex() => $_clearField($_whichOneof(1));

  @$pb.TagNumber(9)
  CreateViewPayloadPB_OneOfSection whichOneOfSection() =>
      _CreateViewPayloadPB_OneOfSectionByTag[$_whichOneof(2)]!;
  @$pb.TagNumber(9)
  void clearOneOfSection() => $_clearField($_whichOneof(2));

  @$pb.TagNumber(10)
  CreateViewPayloadPB_OneOfViewId whichOneOfViewId() =>
      _CreateViewPayloadPB_OneOfViewIdByTag[$_whichOneof(3)]!;
  @$pb.TagNumber(10)
  void clearOneOfViewId() => $_clearField($_whichOneof(3));

  @$pb.TagNumber(11)
  CreateViewPayloadPB_OneOfExtra whichOneOfExtra() =>
      _CreateViewPayloadPB_OneOfExtraByTag[$_whichOneof(4)]!;
  @$pb.TagNumber(11)
  void clearOneOfExtra() => $_clearField($_whichOneof(4));

  @$pb.TagNumber(1)
  $core.String get parentViewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set parentViewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasParentViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearParentViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get thumbnail => $_getSZ(2);
  @$pb.TagNumber(3)
  set thumbnail($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasThumbnail() => $_has(2);
  @$pb.TagNumber(3)
  void clearThumbnail() => $_clearField(3);

  @$pb.TagNumber(4)
  ViewLayoutPB get layout => $_getN(3);
  @$pb.TagNumber(4)
  set layout(ViewLayoutPB value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasLayout() => $_has(3);
  @$pb.TagNumber(4)
  void clearLayout() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get initialData => $_getN(4);
  @$pb.TagNumber(5)
  set initialData($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasInitialData() => $_has(4);
  @$pb.TagNumber(5)
  void clearInitialData() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbMap<$core.String, $core.String> get meta => $_getMap(5);

  @$pb.TagNumber(7)
  $core.bool get setAsCurrent => $_getBF(6);
  @$pb.TagNumber(7)
  set setAsCurrent($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSetAsCurrent() => $_has(6);
  @$pb.TagNumber(7)
  void clearSetAsCurrent() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get index => $_getIZ(7);
  @$pb.TagNumber(8)
  set index($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasIndex() => $_has(7);
  @$pb.TagNumber(8)
  void clearIndex() => $_clearField(8);

  @$pb.TagNumber(9)
  ViewSectionPB get section => $_getN(8);
  @$pb.TagNumber(9)
  set section(ViewSectionPB value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasSection() => $_has(8);
  @$pb.TagNumber(9)
  void clearSection() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get viewId => $_getSZ(9);
  @$pb.TagNumber(10)
  set viewId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasViewId() => $_has(9);
  @$pb.TagNumber(10)
  void clearViewId() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get extra => $_getSZ(10);
  @$pb.TagNumber(11)
  set extra($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasExtra() => $_has(10);
  @$pb.TagNumber(11)
  void clearExtra() => $_clearField(11);
}

class CreateOrphanViewPayloadPB extends $pb.GeneratedMessage {
  factory CreateOrphanViewPayloadPB({
    $core.String? viewId,
    $core.String? name,
    ViewLayoutPB? layout,
    $core.List<$core.int>? initialData,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (name != null) result.name = name;
    if (layout != null) result.layout = layout;
    if (initialData != null) result.initialData = initialData;
    return result;
  }

  CreateOrphanViewPayloadPB._();

  factory CreateOrphanViewPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateOrphanViewPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateOrphanViewPayloadPB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aE<ViewLayoutPB>(3, _omitFieldNames ? '' : 'layout',
        enumValues: ViewLayoutPB.values)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'initialData', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateOrphanViewPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateOrphanViewPayloadPB copyWith(
          void Function(CreateOrphanViewPayloadPB) updates) =>
      super.copyWith((message) => updates(message as CreateOrphanViewPayloadPB))
          as CreateOrphanViewPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateOrphanViewPayloadPB create() => CreateOrphanViewPayloadPB._();
  @$core.override
  CreateOrphanViewPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateOrphanViewPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateOrphanViewPayloadPB>(create);
  static CreateOrphanViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  ViewLayoutPB get layout => $_getN(2);
  @$pb.TagNumber(3)
  set layout(ViewLayoutPB value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasLayout() => $_has(2);
  @$pb.TagNumber(3)
  void clearLayout() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get initialData => $_getN(3);
  @$pb.TagNumber(4)
  set initialData($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasInitialData() => $_has(3);
  @$pb.TagNumber(4)
  void clearInitialData() => $_clearField(4);
}

class ViewIdPB extends $pb.GeneratedMessage {
  factory ViewIdPB({
    $core.String? value,
  }) {
    final result = create();
    if (value != null) result.value = value;
    return result;
  }

  ViewIdPB._();

  factory ViewIdPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ViewIdPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ViewIdPB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ViewIdPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ViewIdPB copyWith(void Function(ViewIdPB) updates) =>
      super.copyWith((message) => updates(message as ViewIdPB)) as ViewIdPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ViewIdPB create() => ViewIdPB._();
  @$core.override
  ViewIdPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ViewIdPB getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ViewIdPB>(create);
  static ViewIdPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get value => $_getSZ(0);
  @$pb.TagNumber(1)
  set value($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => $_clearField(1);
}

class SetPublishNamePB extends $pb.GeneratedMessage {
  factory SetPublishNamePB({
    $core.String? viewId,
    $core.String? newName,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (newName != null) result.newName = newName;
    return result;
  }

  SetPublishNamePB._();

  factory SetPublishNamePB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetPublishNamePB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetPublishNamePB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aOS(2, _omitFieldNames ? '' : 'newName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetPublishNamePB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetPublishNamePB copyWith(void Function(SetPublishNamePB) updates) =>
      super.copyWith((message) => updates(message as SetPublishNamePB))
          as SetPublishNamePB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetPublishNamePB create() => SetPublishNamePB._();
  @$core.override
  SetPublishNamePB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetPublishNamePB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetPublishNamePB>(create);
  static SetPublishNamePB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get newName => $_getSZ(1);
  @$pb.TagNumber(2)
  set newName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNewName() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewName() => $_clearField(2);
}

enum DeletedViewPB_OneOfIndex { index_, notSet }

class DeletedViewPB extends $pb.GeneratedMessage {
  factory DeletedViewPB({
    $core.String? viewId,
    $core.int? index,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (index != null) result.index = index;
    return result;
  }

  DeletedViewPB._();

  factory DeletedViewPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeletedViewPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DeletedViewPB_OneOfIndex>
      _DeletedViewPB_OneOfIndexByTag = {
    2: DeletedViewPB_OneOfIndex.index_,
    0: DeletedViewPB_OneOfIndex.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeletedViewPB',
      createEmptyInstance: create)
    ..oo(0, [2])
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aI(2, _omitFieldNames ? '' : 'index')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletedViewPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeletedViewPB copyWith(void Function(DeletedViewPB) updates) =>
      super.copyWith((message) => updates(message as DeletedViewPB))
          as DeletedViewPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeletedViewPB create() => DeletedViewPB._();
  @$core.override
  DeletedViewPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeletedViewPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeletedViewPB>(create);
  static DeletedViewPB? _defaultInstance;

  @$pb.TagNumber(2)
  DeletedViewPB_OneOfIndex whichOneOfIndex() =>
      _DeletedViewPB_OneOfIndexByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  void clearOneOfIndex() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get index => $_getIZ(1);
  @$pb.TagNumber(2)
  set index($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndex() => $_clearField(2);
}

enum UpdateViewPayloadPB_OneOfName { name, notSet }

enum UpdateViewPayloadPB_OneOfDesc { desc, notSet }

enum UpdateViewPayloadPB_OneOfThumbnail { thumbnail, notSet }

enum UpdateViewPayloadPB_OneOfLayout { layout, notSet }

enum UpdateViewPayloadPB_OneOfIsFavorite { isFavorite, notSet }

enum UpdateViewPayloadPB_OneOfExtra { extra, notSet }

class UpdateViewPayloadPB extends $pb.GeneratedMessage {
  factory UpdateViewPayloadPB({
    $core.String? viewId,
    $core.String? name,
    $core.String? desc,
    $core.String? thumbnail,
    ViewLayoutPB? layout,
    $core.bool? isFavorite,
    $core.String? extra,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (name != null) result.name = name;
    if (desc != null) result.desc = desc;
    if (thumbnail != null) result.thumbnail = thumbnail;
    if (layout != null) result.layout = layout;
    if (isFavorite != null) result.isFavorite = isFavorite;
    if (extra != null) result.extra = extra;
    return result;
  }

  UpdateViewPayloadPB._();

  factory UpdateViewPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateViewPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfName>
      _UpdateViewPayloadPB_OneOfNameByTag = {
    2: UpdateViewPayloadPB_OneOfName.name,
    0: UpdateViewPayloadPB_OneOfName.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfDesc>
      _UpdateViewPayloadPB_OneOfDescByTag = {
    3: UpdateViewPayloadPB_OneOfDesc.desc,
    0: UpdateViewPayloadPB_OneOfDesc.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfThumbnail>
      _UpdateViewPayloadPB_OneOfThumbnailByTag = {
    4: UpdateViewPayloadPB_OneOfThumbnail.thumbnail,
    0: UpdateViewPayloadPB_OneOfThumbnail.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfLayout>
      _UpdateViewPayloadPB_OneOfLayoutByTag = {
    5: UpdateViewPayloadPB_OneOfLayout.layout,
    0: UpdateViewPayloadPB_OneOfLayout.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfIsFavorite>
      _UpdateViewPayloadPB_OneOfIsFavoriteByTag = {
    6: UpdateViewPayloadPB_OneOfIsFavorite.isFavorite,
    0: UpdateViewPayloadPB_OneOfIsFavorite.notSet
  };
  static const $core.Map<$core.int, UpdateViewPayloadPB_OneOfExtra>
      _UpdateViewPayloadPB_OneOfExtraByTag = {
    7: UpdateViewPayloadPB_OneOfExtra.extra,
    0: UpdateViewPayloadPB_OneOfExtra.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateViewPayloadPB',
      createEmptyInstance: create)
    ..oo(0, [2])
    ..oo(1, [3])
    ..oo(2, [4])
    ..oo(3, [5])
    ..oo(4, [6])
    ..oo(5, [7])
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'desc')
    ..aOS(4, _omitFieldNames ? '' : 'thumbnail')
    ..aE<ViewLayoutPB>(5, _omitFieldNames ? '' : 'layout',
        enumValues: ViewLayoutPB.values)
    ..aOB(6, _omitFieldNames ? '' : 'isFavorite')
    ..aOS(7, _omitFieldNames ? '' : 'extra')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateViewPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateViewPayloadPB copyWith(void Function(UpdateViewPayloadPB) updates) =>
      super.copyWith((message) => updates(message as UpdateViewPayloadPB))
          as UpdateViewPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateViewPayloadPB create() => UpdateViewPayloadPB._();
  @$core.override
  UpdateViewPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateViewPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateViewPayloadPB>(create);
  static UpdateViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(2)
  UpdateViewPayloadPB_OneOfName whichOneOfName() =>
      _UpdateViewPayloadPB_OneOfNameByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  void clearOneOfName() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(3)
  UpdateViewPayloadPB_OneOfDesc whichOneOfDesc() =>
      _UpdateViewPayloadPB_OneOfDescByTag[$_whichOneof(1)]!;
  @$pb.TagNumber(3)
  void clearOneOfDesc() => $_clearField($_whichOneof(1));

  @$pb.TagNumber(4)
  UpdateViewPayloadPB_OneOfThumbnail whichOneOfThumbnail() =>
      _UpdateViewPayloadPB_OneOfThumbnailByTag[$_whichOneof(2)]!;
  @$pb.TagNumber(4)
  void clearOneOfThumbnail() => $_clearField($_whichOneof(2));

  @$pb.TagNumber(5)
  UpdateViewPayloadPB_OneOfLayout whichOneOfLayout() =>
      _UpdateViewPayloadPB_OneOfLayoutByTag[$_whichOneof(3)]!;
  @$pb.TagNumber(5)
  void clearOneOfLayout() => $_clearField($_whichOneof(3));

  @$pb.TagNumber(6)
  UpdateViewPayloadPB_OneOfIsFavorite whichOneOfIsFavorite() =>
      _UpdateViewPayloadPB_OneOfIsFavoriteByTag[$_whichOneof(4)]!;
  @$pb.TagNumber(6)
  void clearOneOfIsFavorite() => $_clearField($_whichOneof(4));

  @$pb.TagNumber(7)
  UpdateViewPayloadPB_OneOfExtra whichOneOfExtra() =>
      _UpdateViewPayloadPB_OneOfExtraByTag[$_whichOneof(5)]!;
  @$pb.TagNumber(7)
  void clearOneOfExtra() => $_clearField($_whichOneof(5));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get desc => $_getSZ(2);
  @$pb.TagNumber(3)
  set desc($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDesc() => $_has(2);
  @$pb.TagNumber(3)
  void clearDesc() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get thumbnail => $_getSZ(3);
  @$pb.TagNumber(4)
  set thumbnail($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasThumbnail() => $_has(3);
  @$pb.TagNumber(4)
  void clearThumbnail() => $_clearField(4);

  @$pb.TagNumber(5)
  ViewLayoutPB get layout => $_getN(4);
  @$pb.TagNumber(5)
  set layout(ViewLayoutPB value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasLayout() => $_has(4);
  @$pb.TagNumber(5)
  void clearLayout() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isFavorite => $_getBF(5);
  @$pb.TagNumber(6)
  set isFavorite($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIsFavorite() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsFavorite() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get extra => $_getSZ(6);
  @$pb.TagNumber(7)
  set extra($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasExtra() => $_has(6);
  @$pb.TagNumber(7)
  void clearExtra() => $_clearField(7);
}

class MoveViewPayloadPB extends $pb.GeneratedMessage {
  factory MoveViewPayloadPB({
    $core.String? viewId,
    $core.int? from,
    $core.int? to,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (from != null) result.from = from;
    if (to != null) result.to = to;
    return result;
  }

  MoveViewPayloadPB._();

  factory MoveViewPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MoveViewPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MoveViewPayloadPB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aI(2, _omitFieldNames ? '' : 'from')
    ..aI(3, _omitFieldNames ? '' : 'to')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveViewPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveViewPayloadPB copyWith(void Function(MoveViewPayloadPB) updates) =>
      super.copyWith((message) => updates(message as MoveViewPayloadPB))
          as MoveViewPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MoveViewPayloadPB create() => MoveViewPayloadPB._();
  @$core.override
  MoveViewPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MoveViewPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MoveViewPayloadPB>(create);
  static MoveViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get from => $_getIZ(1);
  @$pb.TagNumber(2)
  set from($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFrom() => $_has(1);
  @$pb.TagNumber(2)
  void clearFrom() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get to => $_getIZ(2);
  @$pb.TagNumber(3)
  set to($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTo() => $_has(2);
  @$pb.TagNumber(3)
  void clearTo() => $_clearField(3);
}

enum MoveNestedViewPayloadPB_OneOfPrevViewId { prevViewId, notSet }

enum MoveNestedViewPayloadPB_OneOfFromSection { fromSection, notSet }

enum MoveNestedViewPayloadPB_OneOfToSection { toSection, notSet }

class MoveNestedViewPayloadPB extends $pb.GeneratedMessage {
  factory MoveNestedViewPayloadPB({
    $core.String? viewId,
    $core.String? newParentId,
    $core.String? prevViewId,
    ViewSectionPB? fromSection,
    ViewSectionPB? toSection,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (newParentId != null) result.newParentId = newParentId;
    if (prevViewId != null) result.prevViewId = prevViewId;
    if (fromSection != null) result.fromSection = fromSection;
    if (toSection != null) result.toSection = toSection;
    return result;
  }

  MoveNestedViewPayloadPB._();

  factory MoveNestedViewPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MoveNestedViewPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, MoveNestedViewPayloadPB_OneOfPrevViewId>
      _MoveNestedViewPayloadPB_OneOfPrevViewIdByTag = {
    3: MoveNestedViewPayloadPB_OneOfPrevViewId.prevViewId,
    0: MoveNestedViewPayloadPB_OneOfPrevViewId.notSet
  };
  static const $core.Map<$core.int, MoveNestedViewPayloadPB_OneOfFromSection>
      _MoveNestedViewPayloadPB_OneOfFromSectionByTag = {
    4: MoveNestedViewPayloadPB_OneOfFromSection.fromSection,
    0: MoveNestedViewPayloadPB_OneOfFromSection.notSet
  };
  static const $core.Map<$core.int, MoveNestedViewPayloadPB_OneOfToSection>
      _MoveNestedViewPayloadPB_OneOfToSectionByTag = {
    5: MoveNestedViewPayloadPB_OneOfToSection.toSection,
    0: MoveNestedViewPayloadPB_OneOfToSection.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MoveNestedViewPayloadPB',
      createEmptyInstance: create)
    ..oo(0, [3])
    ..oo(1, [4])
    ..oo(2, [5])
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aOS(2, _omitFieldNames ? '' : 'newParentId')
    ..aOS(3, _omitFieldNames ? '' : 'prevViewId')
    ..aE<ViewSectionPB>(4, _omitFieldNames ? '' : 'fromSection',
        enumValues: ViewSectionPB.values)
    ..aE<ViewSectionPB>(5, _omitFieldNames ? '' : 'toSection',
        enumValues: ViewSectionPB.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveNestedViewPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveNestedViewPayloadPB copyWith(
          void Function(MoveNestedViewPayloadPB) updates) =>
      super.copyWith((message) => updates(message as MoveNestedViewPayloadPB))
          as MoveNestedViewPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MoveNestedViewPayloadPB create() => MoveNestedViewPayloadPB._();
  @$core.override
  MoveNestedViewPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MoveNestedViewPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MoveNestedViewPayloadPB>(create);
  static MoveNestedViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(3)
  MoveNestedViewPayloadPB_OneOfPrevViewId whichOneOfPrevViewId() =>
      _MoveNestedViewPayloadPB_OneOfPrevViewIdByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  void clearOneOfPrevViewId() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(4)
  MoveNestedViewPayloadPB_OneOfFromSection whichOneOfFromSection() =>
      _MoveNestedViewPayloadPB_OneOfFromSectionByTag[$_whichOneof(1)]!;
  @$pb.TagNumber(4)
  void clearOneOfFromSection() => $_clearField($_whichOneof(1));

  @$pb.TagNumber(5)
  MoveNestedViewPayloadPB_OneOfToSection whichOneOfToSection() =>
      _MoveNestedViewPayloadPB_OneOfToSectionByTag[$_whichOneof(2)]!;
  @$pb.TagNumber(5)
  void clearOneOfToSection() => $_clearField($_whichOneof(2));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get newParentId => $_getSZ(1);
  @$pb.TagNumber(2)
  set newParentId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNewParentId() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewParentId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get prevViewId => $_getSZ(2);
  @$pb.TagNumber(3)
  set prevViewId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPrevViewId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPrevViewId() => $_clearField(3);

  @$pb.TagNumber(4)
  ViewSectionPB get fromSection => $_getN(3);
  @$pb.TagNumber(4)
  set fromSection(ViewSectionPB value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFromSection() => $_has(3);
  @$pb.TagNumber(4)
  void clearFromSection() => $_clearField(4);

  @$pb.TagNumber(5)
  ViewSectionPB get toSection => $_getN(4);
  @$pb.TagNumber(5)
  set toSection(ViewSectionPB value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasToSection() => $_has(4);
  @$pb.TagNumber(5)
  void clearToSection() => $_clearField(5);
}

class UpdateRecentViewPayloadPB extends $pb.GeneratedMessage {
  factory UpdateRecentViewPayloadPB({
    $core.Iterable<$core.String>? viewIds,
    $core.bool? addInRecent,
  }) {
    final result = create();
    if (viewIds != null) result.viewIds.addAll(viewIds);
    if (addInRecent != null) result.addInRecent = addInRecent;
    return result;
  }

  UpdateRecentViewPayloadPB._();

  factory UpdateRecentViewPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateRecentViewPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateRecentViewPayloadPB',
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'viewIds')
    ..aOB(2, _omitFieldNames ? '' : 'addInRecent')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateRecentViewPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateRecentViewPayloadPB copyWith(
          void Function(UpdateRecentViewPayloadPB) updates) =>
      super.copyWith((message) => updates(message as UpdateRecentViewPayloadPB))
          as UpdateRecentViewPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateRecentViewPayloadPB create() => UpdateRecentViewPayloadPB._();
  @$core.override
  UpdateRecentViewPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateRecentViewPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateRecentViewPayloadPB>(create);
  static UpdateRecentViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get viewIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get addInRecent => $_getBF(1);
  @$pb.TagNumber(2)
  set addInRecent($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAddInRecent() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddInRecent() => $_clearField(2);
}

class UpdateViewVisibilityStatusPayloadPB extends $pb.GeneratedMessage {
  factory UpdateViewVisibilityStatusPayloadPB({
    $core.Iterable<$core.String>? viewIds,
    $core.bool? isPublic,
  }) {
    final result = create();
    if (viewIds != null) result.viewIds.addAll(viewIds);
    if (isPublic != null) result.isPublic = isPublic;
    return result;
  }

  UpdateViewVisibilityStatusPayloadPB._();

  factory UpdateViewVisibilityStatusPayloadPB.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateViewVisibilityStatusPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateViewVisibilityStatusPayloadPB',
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'viewIds')
    ..aOB(2, _omitFieldNames ? '' : 'isPublic')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateViewVisibilityStatusPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateViewVisibilityStatusPayloadPB copyWith(
          void Function(UpdateViewVisibilityStatusPayloadPB) updates) =>
      super.copyWith((message) =>
              updates(message as UpdateViewVisibilityStatusPayloadPB))
          as UpdateViewVisibilityStatusPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateViewVisibilityStatusPayloadPB create() =>
      UpdateViewVisibilityStatusPayloadPB._();
  @$core.override
  UpdateViewVisibilityStatusPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateViewVisibilityStatusPayloadPB getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          UpdateViewVisibilityStatusPayloadPB>(create);
  static UpdateViewVisibilityStatusPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get viewIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get isPublic => $_getBF(1);
  @$pb.TagNumber(2)
  set isPublic($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsPublic() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsPublic() => $_clearField(2);
}

enum DuplicateViewPayloadPB_OneOfParentViewId { parentViewId, notSet }

enum DuplicateViewPayloadPB_OneOfSuffix { suffix, notSet }

class DuplicateViewPayloadPB extends $pb.GeneratedMessage {
  factory DuplicateViewPayloadPB({
    $core.String? viewId,
    $core.bool? openAfterDuplicate,
    $core.bool? includeChildren,
    $core.String? parentViewId,
    $core.String? suffix,
    $core.bool? syncAfterCreate,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (openAfterDuplicate != null)
      result.openAfterDuplicate = openAfterDuplicate;
    if (includeChildren != null) result.includeChildren = includeChildren;
    if (parentViewId != null) result.parentViewId = parentViewId;
    if (suffix != null) result.suffix = suffix;
    if (syncAfterCreate != null) result.syncAfterCreate = syncAfterCreate;
    return result;
  }

  DuplicateViewPayloadPB._();

  factory DuplicateViewPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DuplicateViewPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DuplicateViewPayloadPB_OneOfParentViewId>
      _DuplicateViewPayloadPB_OneOfParentViewIdByTag = {
    4: DuplicateViewPayloadPB_OneOfParentViewId.parentViewId,
    0: DuplicateViewPayloadPB_OneOfParentViewId.notSet
  };
  static const $core.Map<$core.int, DuplicateViewPayloadPB_OneOfSuffix>
      _DuplicateViewPayloadPB_OneOfSuffixByTag = {
    5: DuplicateViewPayloadPB_OneOfSuffix.suffix,
    0: DuplicateViewPayloadPB_OneOfSuffix.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DuplicateViewPayloadPB',
      createEmptyInstance: create)
    ..oo(0, [4])
    ..oo(1, [5])
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aOB(2, _omitFieldNames ? '' : 'openAfterDuplicate')
    ..aOB(3, _omitFieldNames ? '' : 'includeChildren')
    ..aOS(4, _omitFieldNames ? '' : 'parentViewId')
    ..aOS(5, _omitFieldNames ? '' : 'suffix')
    ..aOB(6, _omitFieldNames ? '' : 'syncAfterCreate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DuplicateViewPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DuplicateViewPayloadPB copyWith(
          void Function(DuplicateViewPayloadPB) updates) =>
      super.copyWith((message) => updates(message as DuplicateViewPayloadPB))
          as DuplicateViewPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DuplicateViewPayloadPB create() => DuplicateViewPayloadPB._();
  @$core.override
  DuplicateViewPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DuplicateViewPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DuplicateViewPayloadPB>(create);
  static DuplicateViewPayloadPB? _defaultInstance;

  @$pb.TagNumber(4)
  DuplicateViewPayloadPB_OneOfParentViewId whichOneOfParentViewId() =>
      _DuplicateViewPayloadPB_OneOfParentViewIdByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(4)
  void clearOneOfParentViewId() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(5)
  DuplicateViewPayloadPB_OneOfSuffix whichOneOfSuffix() =>
      _DuplicateViewPayloadPB_OneOfSuffixByTag[$_whichOneof(1)]!;
  @$pb.TagNumber(5)
  void clearOneOfSuffix() => $_clearField($_whichOneof(1));

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get openAfterDuplicate => $_getBF(1);
  @$pb.TagNumber(2)
  set openAfterDuplicate($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOpenAfterDuplicate() => $_has(1);
  @$pb.TagNumber(2)
  void clearOpenAfterDuplicate() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get includeChildren => $_getBF(2);
  @$pb.TagNumber(3)
  set includeChildren($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIncludeChildren() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncludeChildren() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get parentViewId => $_getSZ(3);
  @$pb.TagNumber(4)
  set parentViewId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasParentViewId() => $_has(3);
  @$pb.TagNumber(4)
  void clearParentViewId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get suffix => $_getSZ(4);
  @$pb.TagNumber(5)
  set suffix($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSuffix() => $_has(4);
  @$pb.TagNumber(5)
  void clearSuffix() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get syncAfterCreate => $_getBF(5);
  @$pb.TagNumber(6)
  set syncAfterCreate($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSyncAfterCreate() => $_has(5);
  @$pb.TagNumber(6)
  void clearSyncAfterCreate() => $_clearField(6);
}

class SharePageWithUserPayloadPB extends $pb.GeneratedMessage {
  factory SharePageWithUserPayloadPB({
    $core.String? viewId,
    $core.Iterable<$core.String>? emails,
    AFAccessLevelPB? accessLevel,
    $core.bool? autoConfirm,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (emails != null) result.emails.addAll(emails);
    if (accessLevel != null) result.accessLevel = accessLevel;
    if (autoConfirm != null) result.autoConfirm = autoConfirm;
    return result;
  }

  SharePageWithUserPayloadPB._();

  factory SharePageWithUserPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SharePageWithUserPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SharePageWithUserPayloadPB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..pPS(2, _omitFieldNames ? '' : 'emails')
    ..aE<AFAccessLevelPB>(3, _omitFieldNames ? '' : 'accessLevel',
        enumValues: AFAccessLevelPB.values)
    ..aOB(4, _omitFieldNames ? '' : 'autoConfirm')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SharePageWithUserPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SharePageWithUserPayloadPB copyWith(
          void Function(SharePageWithUserPayloadPB) updates) =>
      super.copyWith(
              (message) => updates(message as SharePageWithUserPayloadPB))
          as SharePageWithUserPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SharePageWithUserPayloadPB create() => SharePageWithUserPayloadPB._();
  @$core.override
  SharePageWithUserPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SharePageWithUserPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SharePageWithUserPayloadPB>(create);
  static SharePageWithUserPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get emails => $_getList(1);

  @$pb.TagNumber(3)
  AFAccessLevelPB get accessLevel => $_getN(2);
  @$pb.TagNumber(3)
  set accessLevel(AFAccessLevelPB value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasAccessLevel() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccessLevel() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get autoConfirm => $_getBF(3);
  @$pb.TagNumber(4)
  set autoConfirm($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAutoConfirm() => $_has(3);
  @$pb.TagNumber(4)
  void clearAutoConfirm() => $_clearField(4);
}

class RemoveUserFromSharedPagePayloadPB extends $pb.GeneratedMessage {
  factory RemoveUserFromSharedPagePayloadPB({
    $core.String? viewId,
    $core.Iterable<$core.String>? emails,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (emails != null) result.emails.addAll(emails);
    return result;
  }

  RemoveUserFromSharedPagePayloadPB._();

  factory RemoveUserFromSharedPagePayloadPB.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RemoveUserFromSharedPagePayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RemoveUserFromSharedPagePayloadPB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..pPS(2, _omitFieldNames ? '' : 'emails')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoveUserFromSharedPagePayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RemoveUserFromSharedPagePayloadPB copyWith(
          void Function(RemoveUserFromSharedPagePayloadPB) updates) =>
      super.copyWith((message) =>
              updates(message as RemoveUserFromSharedPagePayloadPB))
          as RemoveUserFromSharedPagePayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RemoveUserFromSharedPagePayloadPB create() =>
      RemoveUserFromSharedPagePayloadPB._();
  @$core.override
  RemoveUserFromSharedPagePayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RemoveUserFromSharedPagePayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RemoveUserFromSharedPagePayloadPB>(
          create);
  static RemoveUserFromSharedPagePayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get emails => $_getList(1);
}

enum SharedUserPB_OneOfAvatarUrl { avatarUrl, notSet }

enum SharedUserPB_OneOfUserId { userId, notSet }

class SharedUserPB extends $pb.GeneratedMessage {
  factory SharedUserPB({
    $core.String? email,
    $core.String? name,
    AFRolePB? role,
    AFAccessLevelPB? accessLevel,
    $core.String? avatarUrl,
    $core.String? userId,
  }) {
    final result = create();
    if (email != null) result.email = email;
    if (name != null) result.name = name;
    if (role != null) result.role = role;
    if (accessLevel != null) result.accessLevel = accessLevel;
    if (avatarUrl != null) result.avatarUrl = avatarUrl;
    if (userId != null) result.userId = userId;
    return result;
  }

  SharedUserPB._();

  factory SharedUserPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SharedUserPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, SharedUserPB_OneOfAvatarUrl>
      _SharedUserPB_OneOfAvatarUrlByTag = {
    5: SharedUserPB_OneOfAvatarUrl.avatarUrl,
    0: SharedUserPB_OneOfAvatarUrl.notSet
  };
  static const $core.Map<$core.int, SharedUserPB_OneOfUserId>
      _SharedUserPB_OneOfUserIdByTag = {
    6: SharedUserPB_OneOfUserId.userId,
    0: SharedUserPB_OneOfUserId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SharedUserPB',
      createEmptyInstance: create)
    ..oo(0, [5])
    ..oo(1, [6])
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aE<AFRolePB>(3, _omitFieldNames ? '' : 'role',
        enumValues: AFRolePB.values)
    ..aE<AFAccessLevelPB>(4, _omitFieldNames ? '' : 'accessLevel',
        enumValues: AFAccessLevelPB.values)
    ..aOS(5, _omitFieldNames ? '' : 'avatarUrl')
    ..aOS(6, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SharedUserPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SharedUserPB copyWith(void Function(SharedUserPB) updates) =>
      super.copyWith((message) => updates(message as SharedUserPB))
          as SharedUserPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SharedUserPB create() => SharedUserPB._();
  @$core.override
  SharedUserPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SharedUserPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SharedUserPB>(create);
  static SharedUserPB? _defaultInstance;

  @$pb.TagNumber(5)
  SharedUserPB_OneOfAvatarUrl whichOneOfAvatarUrl() =>
      _SharedUserPB_OneOfAvatarUrlByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(5)
  void clearOneOfAvatarUrl() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(6)
  SharedUserPB_OneOfUserId whichOneOfUserId() =>
      _SharedUserPB_OneOfUserIdByTag[$_whichOneof(1)]!;
  @$pb.TagNumber(6)
  void clearOneOfUserId() => $_clearField($_whichOneof(1));

  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  AFRolePB get role => $_getN(2);
  @$pb.TagNumber(3)
  set role(AFRolePB value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearRole() => $_clearField(3);

  @$pb.TagNumber(4)
  AFAccessLevelPB get accessLevel => $_getN(3);
  @$pb.TagNumber(4)
  set accessLevel(AFAccessLevelPB value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasAccessLevel() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccessLevel() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get avatarUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set avatarUrl($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAvatarUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvatarUrl() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get userId => $_getSZ(5);
  @$pb.TagNumber(6)
  set userId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasUserId() => $_has(5);
  @$pb.TagNumber(6)
  void clearUserId() => $_clearField(6);
}

class RepeatedSharedUserPB extends $pb.GeneratedMessage {
  factory RepeatedSharedUserPB({
    $core.Iterable<SharedUserPB>? items,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    return result;
  }

  RepeatedSharedUserPB._();

  factory RepeatedSharedUserPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RepeatedSharedUserPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RepeatedSharedUserPB',
      createEmptyInstance: create)
    ..pPM<SharedUserPB>(1, _omitFieldNames ? '' : 'items',
        subBuilder: SharedUserPB.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedSharedUserPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedSharedUserPB copyWith(void Function(RepeatedSharedUserPB) updates) =>
      super.copyWith((message) => updates(message as RepeatedSharedUserPB))
          as RepeatedSharedUserPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedSharedUserPB create() => RepeatedSharedUserPB._();
  @$core.override
  RepeatedSharedUserPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RepeatedSharedUserPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RepeatedSharedUserPB>(create);
  static RepeatedSharedUserPB? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SharedUserPB> get items => $_getList(0);
}

class GetSharedUsersPayloadPB extends $pb.GeneratedMessage {
  factory GetSharedUsersPayloadPB({
    $core.String? viewId,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    return result;
  }

  GetSharedUsersPayloadPB._();

  factory GetSharedUsersPayloadPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetSharedUsersPayloadPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetSharedUsersPayloadPB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSharedUsersPayloadPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSharedUsersPayloadPB copyWith(
          void Function(GetSharedUsersPayloadPB) updates) =>
      super.copyWith((message) => updates(message as GetSharedUsersPayloadPB))
          as GetSharedUsersPayloadPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetSharedUsersPayloadPB create() => GetSharedUsersPayloadPB._();
  @$core.override
  GetSharedUsersPayloadPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetSharedUsersPayloadPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetSharedUsersPayloadPB>(create);
  static GetSharedUsersPayloadPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);
}

enum SharedViewPB_OneOfWorkspaceId { workspaceId, notSet }

class SharedViewPB extends $pb.GeneratedMessage {
  factory SharedViewPB({
    ViewPB? view,
    AFAccessLevelPB? accessLevel,
    $core.String? workspaceId,
  }) {
    final result = create();
    if (view != null) result.view = view;
    if (accessLevel != null) result.accessLevel = accessLevel;
    if (workspaceId != null) result.workspaceId = workspaceId;
    return result;
  }

  SharedViewPB._();

  factory SharedViewPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SharedViewPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, SharedViewPB_OneOfWorkspaceId>
      _SharedViewPB_OneOfWorkspaceIdByTag = {
    3: SharedViewPB_OneOfWorkspaceId.workspaceId,
    0: SharedViewPB_OneOfWorkspaceId.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SharedViewPB',
      createEmptyInstance: create)
    ..oo(0, [3])
    ..aOM<ViewPB>(1, _omitFieldNames ? '' : 'view', subBuilder: ViewPB.create)
    ..aE<AFAccessLevelPB>(2, _omitFieldNames ? '' : 'accessLevel',
        enumValues: AFAccessLevelPB.values)
    ..aOS(3, _omitFieldNames ? '' : 'workspaceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SharedViewPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SharedViewPB copyWith(void Function(SharedViewPB) updates) =>
      super.copyWith((message) => updates(message as SharedViewPB))
          as SharedViewPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SharedViewPB create() => SharedViewPB._();
  @$core.override
  SharedViewPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SharedViewPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SharedViewPB>(create);
  static SharedViewPB? _defaultInstance;

  @$pb.TagNumber(3)
  SharedViewPB_OneOfWorkspaceId whichOneOfWorkspaceId() =>
      _SharedViewPB_OneOfWorkspaceIdByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  void clearOneOfWorkspaceId() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ViewPB get view => $_getN(0);
  @$pb.TagNumber(1)
  set view(ViewPB value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasView() => $_has(0);
  @$pb.TagNumber(1)
  void clearView() => $_clearField(1);
  @$pb.TagNumber(1)
  ViewPB ensureView() => $_ensure(0);

  @$pb.TagNumber(2)
  AFAccessLevelPB get accessLevel => $_getN(1);
  @$pb.TagNumber(2)
  set accessLevel(AFAccessLevelPB value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAccessLevel() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccessLevel() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get workspaceId => $_getSZ(2);
  @$pb.TagNumber(3)
  set workspaceId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWorkspaceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearWorkspaceId() => $_clearField(3);
}

class RepeatedSharedViewResponsePB extends $pb.GeneratedMessage {
  factory RepeatedSharedViewResponsePB({
    $core.Iterable<SharedViewPB>? sharedViews,
  }) {
    final result = create();
    if (sharedViews != null) result.sharedViews.addAll(sharedViews);
    return result;
  }

  RepeatedSharedViewResponsePB._();

  factory RepeatedSharedViewResponsePB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RepeatedSharedViewResponsePB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RepeatedSharedViewResponsePB',
      createEmptyInstance: create)
    ..pPM<SharedViewPB>(1, _omitFieldNames ? '' : 'sharedViews',
        subBuilder: SharedViewPB.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedSharedViewResponsePB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RepeatedSharedViewResponsePB copyWith(
          void Function(RepeatedSharedViewResponsePB) updates) =>
      super.copyWith(
              (message) => updates(message as RepeatedSharedViewResponsePB))
          as RepeatedSharedViewResponsePB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RepeatedSharedViewResponsePB create() =>
      RepeatedSharedViewResponsePB._();
  @$core.override
  RepeatedSharedViewResponsePB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RepeatedSharedViewResponsePB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RepeatedSharedViewResponsePB>(create);
  static RepeatedSharedViewResponsePB? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<SharedViewPB> get sharedViews => $_getList(0);
}

class GetSharedViewSectionResponsePB extends $pb.GeneratedMessage {
  factory GetSharedViewSectionResponsePB({
    SharedViewSectionPB? section,
  }) {
    final result = create();
    if (section != null) result.section = section;
    return result;
  }

  GetSharedViewSectionResponsePB._();

  factory GetSharedViewSectionResponsePB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetSharedViewSectionResponsePB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetSharedViewSectionResponsePB',
      createEmptyInstance: create)
    ..aE<SharedViewSectionPB>(1, _omitFieldNames ? '' : 'section',
        enumValues: SharedViewSectionPB.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSharedViewSectionResponsePB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetSharedViewSectionResponsePB copyWith(
          void Function(GetSharedViewSectionResponsePB) updates) =>
      super.copyWith(
              (message) => updates(message as GetSharedViewSectionResponsePB))
          as GetSharedViewSectionResponsePB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetSharedViewSectionResponsePB create() =>
      GetSharedViewSectionResponsePB._();
  @$core.override
  GetSharedViewSectionResponsePB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetSharedViewSectionResponsePB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetSharedViewSectionResponsePB>(create);
  static GetSharedViewSectionResponsePB? _defaultInstance;

  @$pb.TagNumber(1)
  SharedViewSectionPB get section => $_getN(0);
  @$pb.TagNumber(1)
  set section(SharedViewSectionPB value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSection() => $_has(0);
  @$pb.TagNumber(1)
  void clearSection() => $_clearField(1);
}

class SaveSharedViewMetaPB extends $pb.GeneratedMessage {
  factory SaveSharedViewMetaPB({
    $core.String? viewId,
    $core.String? workspaceId,
    $core.String? viewName,
    $core.int? viewLayout,
    $core.int? permissionId,
  }) {
    final result = create();
    if (viewId != null) result.viewId = viewId;
    if (workspaceId != null) result.workspaceId = workspaceId;
    if (viewName != null) result.viewName = viewName;
    if (viewLayout != null) result.viewLayout = viewLayout;
    if (permissionId != null) result.permissionId = permissionId;
    return result;
  }

  SaveSharedViewMetaPB._();

  factory SaveSharedViewMetaPB.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SaveSharedViewMetaPB.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SaveSharedViewMetaPB',
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'viewId')
    ..aOS(2, _omitFieldNames ? '' : 'workspaceId')
    ..aOS(3, _omitFieldNames ? '' : 'viewName')
    ..aI(4, _omitFieldNames ? '' : 'viewLayout')
    ..aI(5, _omitFieldNames ? '' : 'permissionId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SaveSharedViewMetaPB clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SaveSharedViewMetaPB copyWith(void Function(SaveSharedViewMetaPB) updates) =>
      super.copyWith((message) => updates(message as SaveSharedViewMetaPB))
          as SaveSharedViewMetaPB;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SaveSharedViewMetaPB create() => SaveSharedViewMetaPB._();
  @$core.override
  SaveSharedViewMetaPB createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SaveSharedViewMetaPB getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SaveSharedViewMetaPB>(create);
  static SaveSharedViewMetaPB? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get viewId => $_getSZ(0);
  @$pb.TagNumber(1)
  set viewId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasViewId() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get workspaceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set workspaceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWorkspaceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearWorkspaceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get viewName => $_getSZ(2);
  @$pb.TagNumber(3)
  set viewName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasViewName() => $_has(2);
  @$pb.TagNumber(3)
  void clearViewName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get viewLayout => $_getIZ(3);
  @$pb.TagNumber(4)
  set viewLayout($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasViewLayout() => $_has(3);
  @$pb.TagNumber(4)
  void clearViewLayout() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get permissionId => $_getIZ(4);
  @$pb.TagNumber(5)
  set permissionId($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPermissionId() => $_has(4);
  @$pb.TagNumber(5)
  void clearPermissionId() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
